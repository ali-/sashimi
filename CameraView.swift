import AVFoundation
import AVKit
import Photos
import SwiftUI

@main
struct CameraApp: App {
	var body: some Scene {
		WindowGroup {
			CameraView().statusBarHidden(true)
		}
	}
}

struct CameraView: View {
	@StateObject private var cameraModel = CameraModel()
	@State private var selectionSpeed = 17
	@State private var selectionGPS = 0
	@State private var selectionISO = 0
	@State private var selectionTimer = 0
	private let viewfinderHeight = UIScreen.main.bounds.width * 4 / 3
	private let optionsGPS: [String] = ["OFF", "ON"]
	private let optionsISO: [Int] = [
		100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000,
		1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000
	]
	private let optionsSpeed: [Int] = [
		1, 2, 3, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30, 40, 50, 60, 80, 100, 125, 160,
		200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000
	]
	private let optionsTimer: [Int] = [0, 1, 2, 3, 5, 10, 15]
	
	var body: some View {
		VStack {
			if cameraModel.isAuthorized {
				Spacer()
					.frame(height: 50)
				
				ZStack {
					CameraPreview(cameraModel: cameraModel)
						.onTapGesture {
							cameraModel.capturePhoto()
						}
					if cameraModel.isShowingFlash {
						Text(" ")
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.background(.black)
					}
				}
				.frame(height: viewfinderHeight)
				
				HStack {
					HStack {
						ZStack {
							SettingSelector(selection: $selectionISO, name: "ISO", options: optionsISO)
						}
						.onChange(of: selectionISO) {
							cameraModel.settingISO = Float(optionsISO[selectionISO])
							cameraModel.updateSettings()
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.rotationEffect(.degrees(90.0))
						.foregroundColor(.white)
						.clipped()
						
						ZStack {
							SettingSelector(selection: $selectionSpeed, name: "SHUTTER", options: optionsSpeed)
						}
						.onChange(of: selectionSpeed) {
							let denom = optionsSpeed[selectionSpeed]
							cameraModel.settingSpeed = CMTimeMake(value: 1, timescale: Int32(denom))
							cameraModel.updateSettings()
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.rotationEffect(.degrees(90.0))
						.foregroundColor(.white)
						.clipped()
						
						ZStack {
							SettingSelector(selection: $selectionTimer, name: "TIMER", options: optionsTimer)
						}
						.onChange(of: selectionTimer) {
							cameraModel.settingTimer = optionsTimer[selectionTimer]
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.rotationEffect(.degrees(90.0))
						.foregroundColor(.white)
						.clipped()
						
						ZStack {
							SettingSelector(selection: $selectionGPS, name: "GPS", options: optionsGPS)
						}
						.onChange(of: selectionGPS) {
							if selectionGPS == 0 {
								cameraModel.settingGPS = false
								cameraModel.stopLocationUpdates()
							}
							else {
								cameraModel.settingGPS = true
								cameraModel.startLocationUpdates()
							}
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.rotationEffect(.degrees(90.0))
						.foregroundColor(.white)
						.clipped()
					}
					.frame(maxWidth: .infinity)
					.font(.system(.body, design: .monospaced))
				}
			}
			else if cameraModel.showPermissionAlert {
				VStack {
					Text("Camera access is required")
					Button("Open Settings") {
						if let url = URL(string: UIApplication.openSettingsURLString) {
							UIApplication.shared.open(url)
						}
					}
				}
			}
			else {
				ProgressView()
			}
		}
		.background(.black)
		.onAppear {
			cameraModel.checkPermission()
		}
	}
}

struct CameraPreview: UIViewControllerRepresentable {
	@ObservedObject var cameraModel: CameraModel
	
	func makeUIViewController(context: Context) -> UIViewController {
		let controller = UIViewController()
		let interaction = AVCaptureEventInteraction { event in
			if event.phase == .ended { self.cameraModel.capturePhoto() }
		}
		controller.view.addInteraction(interaction)
		let previewLayer = AVCaptureVideoPreviewLayer(session: cameraModel.captureSession)
		previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
		previewLayer.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 4 / 3)
		controller.view.layer.addSublayer(previewLayer)
		return controller
	}
	
	func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct SettingSelector: View {
	@Binding var selection: Int
	let name: String
	let options: [Any]
	
	var body: some View {
		Text(name)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.baselineOffset(25)
		TabView(selection: $selection) {
					ForEach(0..<options.count, id: \.self) { index in
						Text(getText(name: name, value: options[index]))
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.baselineOffset(-25)
							.tag(index)
					}
				}
				.tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
	}
	
	private func getText(name: String, value: Any) -> String {
		switch name {
			case "SHUTTER":
				return "1/\(value)"
			
			case "TIMER":
				return "\(value)s"
			
			default:
				return "\(value)"
		}
	}
}

class CameraModel: NSObject, ObservableObject {
	@Published var canCapturePhoto = true
	@Published var currentLocation: CLLocation?
	@Published var isAuthorized = false
	@Published var isShowingFlash = false
	// TODO: These values should be saved between sessions
	@Published var settingGPS: Bool = false
	@Published var settingISO: Float = 100.0
	@Published var settingSpeed: CMTime = CMTimeMake(value: 1, timescale: 100)
	@Published var settingTimer: Int = 0
	// ----------
	@Published var showPermissionAlert = false
	let captureSession = AVCaptureSession()
	private let locationManager = CLLocationManager()
	private let photoOutput = AVCapturePhotoOutput()
	private let sessionQueue = DispatchQueue(label: "cameraSessionQueue")
	private var videoDeviceInput: AVCaptureDeviceInput? = nil
	
	func capturePhoto() {
		DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(settingTimer)) {
			self.isShowingFlash = true
			self.sessionQueue.async {
				// TODO: Ensure RAW capture is available before getting here ever
				let settings = AVCapturePhotoSettings(rawPixelFormatType: self.photoOutput.availableRawPhotoPixelFormatTypes.first!)
				if let codec = settings.availableRawEmbeddedThumbnailPhotoCodecTypes.first {
					let dimensions = settings.maxPhotoDimensions
					settings.rawEmbeddedThumbnailPhotoFormat = [
						AVVideoCodecKey as String: codec,
						AVVideoWidthKey as String: dimensions.width,
						AVVideoHeightKey as String: dimensions.height
					]
				}
				settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
				
				if let connection = self.photoOutput.connection(with: .video) {
					connection.videoRotationAngle = 0
				}
				
				if self.settingGPS, let location = self.currentLocation {
					settings.metadata = [kCGImagePropertyGPSDictionary as String: self.gpsMetadata(from: location)]
				}
				
				self.photoOutput.capturePhoto(with: settings, delegate: self)
				DispatchQueue.main.async {
					self.canCapturePhoto = false
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + .seconds(self.settingTimer)) {
						self.canCapturePhoto = true
					}
				}
				
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + CMTimeGetSeconds(self.settingSpeed)) {
					self.isShowingFlash = false
				}
			}
		}
	}
	
	func checkPermission() {
		switch AVCaptureDevice.authorizationStatus(for: .video) {
			case .authorized:
				DispatchQueue.main.async {
					self.isAuthorized = true
					self.setupCamera()
				}
			
			case .notDetermined:
				AVCaptureDevice.requestAccess(for: .video) { granted in
					DispatchQueue.main.async {
						self.isAuthorized = granted
						if granted { self.setupCamera(); return }
						self.showPermissionAlert = true
					}
				}
			
			case .denied, .restricted:
				DispatchQueue.main.async {
					self.showPermissionAlert = true
				}
			
			@unknown default:
				DispatchQueue.main.async {
					self.showPermissionAlert = true
				}
		}
	}
	
	func startLocationUpdates() {
		locationManager.delegate = self
		locationManager.desiredAccuracy = kCLLocationAccuracyBest
		locationManager.requestWhenInUseAuthorization()
		if #available(iOS 14.0, *) {
			locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "CameraUsage")
		}
		locationManager.startUpdatingLocation()
	}
	
	func stopLocationUpdates() {
		locationManager.stopUpdatingLocation()
	}
	
	func updateSettings() {
		sessionQueue.async {
			guard let device = self.videoDeviceInput?.device else { return }
			try? device.lockForConfiguration()
			device.setExposureModeCustom(duration: self.settingSpeed, iso: self.settingISO, completionHandler: nil)
			device.unlockForConfiguration()
		}
	}
	
	private func gpsMetadata(from location: CLLocation) -> [String: Any] {
		var gps: [String: Any] = [:]
		let formatter = DateFormatter()
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "HH:mm:ss.SS"
		gps[kCGImagePropertyGPSLatitude as String] = abs(location.coordinate.latitude)
		gps[kCGImagePropertyGPSLatitudeRef as String] = location.coordinate.latitude >= 0 ? "N" : "S"
		gps[kCGImagePropertyGPSLongitude as String] = abs(location.coordinate.longitude)
		gps[kCGImagePropertyGPSLongitudeRef as String] = location.coordinate.longitude >= 0 ? "E" : "W"
		gps[kCGImagePropertyGPSAltitude as String] = location.altitude
		gps[kCGImagePropertyGPSAltitudeRef as String] = location.altitude < 0 ? 1 : 0
		gps[kCGImagePropertyGPSTimeStamp as String] = formatter.string(from: location.timestamp)
		gps[kCGImagePropertyGPSDateStamp as String] = DateFormatter.localizedString(from: location.timestamp, dateStyle: .short, timeStyle: .none)
		return gps
	}
	
	private func setupCamera() {
		sessionQueue.async {
			guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
				let input = try? AVCaptureDeviceInput(device: device) else { return }

			self.captureSession.beginConfiguration()
			if self.captureSession.canAddInput(input) { self.captureSession.addInput(input) }
			if self.captureSession.canAddOutput(self.photoOutput) { self.captureSession.addOutput(self.photoOutput) }
			self.photoOutput.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
			self.captureSession.sessionPreset = .photo
			self.captureSession.commitConfiguration()
			self.captureSession.startRunning()
			self.videoDeviceInput = input
		}
	}
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
	func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
		guard error == nil, let photoData = photo.fileDataRepresentation() else { return }
		PHPhotoLibrary.requestAuthorization { status in
			guard status == .authorized else { return }
			PHPhotoLibrary.shared().performChanges({
				let creationRequest = PHAssetCreationRequest.forAsset()
				creationRequest.addResource(with: .photo, data: photoData, options: nil)
			})
		}
	}
}

extension CameraModel: CLLocationManagerDelegate {
	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		self.currentLocation = locations.last
	}
}
