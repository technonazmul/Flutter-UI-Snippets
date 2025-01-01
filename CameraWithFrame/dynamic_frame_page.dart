import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';

class DynamicFramePage extends StatefulWidget {
  final Map<String, dynamic> patientInfo;

  const DynamicFramePage({Key? key, required this.patientInfo})
      : super(key: key);

  @override
  _DynamicFramePageState createState() => _DynamicFramePageState();
}

class _DynamicFramePageState extends State<DynamicFramePage> {
  late CameraController _cameraController;
  late List<CameraDescription> _cameras;
  bool _isInitialized = false;
  final GlobalKey _globalKey = GlobalKey();
  File? _capturedImageFile;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    _cameraController = CameraController(_cameras[0], ResolutionPreset.high);
    await _cameraController.initialize();
    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    try {
      // Capture photo
      final XFile photo = await _cameraController.takePicture();

      setState(() {
        _capturedImageFile = File(photo.path);
      });
    } catch (e) {
      print('Error capturing photo: $e');
    }
  }

  Future<void> _saveCompositeImage() async {
    try {
      if (_capturedImageFile == null) {
        print('No captured image to combine with frame');
        return;
      }

      // Load the captured image
      final capturedImage =
          await decodeImageFromList(await _capturedImageFile!.readAsBytes());

      // Get the frame boundary
      final boundary = _globalKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final frameImage = await boundary.toImage();

      // Combine the captured image and frame
      final pictureRecorder = ui.PictureRecorder();
      final canvas = Canvas(pictureRecorder);

      // Draw the captured image
      final paint = Paint();
      canvas.drawImageRect(
        capturedImage,
        Rect.fromLTWH(0, 0, capturedImage.width.toDouble(),
            capturedImage.height.toDouble()),
        Rect.fromLTWH(
            0, 0, frameImage.width.toDouble(), frameImage.height.toDouble()),
        paint,
      );

      // Draw the frame on top
      canvas.drawImage(frameImage, Offset.zero, paint);

      // Generate the final composite image
      final compositeImage = await pictureRecorder
          .endRecording()
          .toImage(frameImage.width, frameImage.height);
      final byteData =
          await compositeImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final compositeImageBytes = byteData.buffer.asUint8List();
        Navigator.pop(context, compositeImageBytes);
      } else {
        print('Failed to generate composite image');
      }
    } catch (e) {
      print('Error generating composite image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientInfo = widget.patientInfo;

    return Scaffold(
      appBar: AppBar(title: const Text("Dynamic Frame")),
      body: _isInitialized
          ? Stack(
              children: [
                if (_capturedImageFile == null)
                  // Camera Preview
                  Positioned.fill(
                    child: CameraPreview(_cameraController),
                  )
                else
                  // Display the captured image
                  Positioned.fill(
                    child: Image.file(
                      _capturedImageFile!,
                      fit: BoxFit.cover,
                    ),
                  ),

                // Frame Overlay
                if (_capturedImageFile != null || _isInitialized)
                  Positioned.fill(
                    child: RepaintBoundary(
                      key: _globalKey,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue, width: 8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Top Frame Section
                            Container(
                              color: Colors.white.withOpacity(0.8),
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Text(
                                    "DocBee",
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Bottom Frame Section (Patient Info)
                            Container(
                              color: Colors.white.withOpacity(0.8),
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Name: ${patientInfo['name']}",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  Text(
                                    "Age: ${patientInfo['age']}",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  Text(
                                    "Gender: ${patientInfo['gender']}",
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Capture and Save Buttons
                // Capture and Save Buttons
                if (_capturedImageFile == null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: FloatingActionButton(
                        onPressed: _capturePhoto,
                        child: const Icon(Icons.camera),
                      ),
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Recapture Button
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _capturedImageFile =
                                    null; // Reset the captured image
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Colors.grey, // Set background color
                            ),
                            child: const Text("Recapture"),
                          ),

                          // Save Image with Frame Button
                          ElevatedButton(
                            onPressed: _saveCompositeImage,
                            child: const Text("Send to Patient"),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
