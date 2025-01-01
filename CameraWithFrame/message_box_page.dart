import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import './dynamic_frame_page.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class MessageBoxPage extends StatefulWidget {
  final String bookingId;
  const MessageBoxPage({super.key, required this.bookingId});

  @override
  _MessageBoxPageState createState() => _MessageBoxPageState();
}

class _MessageBoxPageState extends State<MessageBoxPage> {
  late IO.Socket socket;
  List<dynamic> messages = [];
  final TextEditingController _messageController = TextEditingController();
  late String _doctorId = '';
  late Map<String, dynamic> _userData;

  bool _isTyping = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _messageController.addListener(_onTyping);
    _connectSocket();
  }

  @override
  void dispose() {
    if (socket.connected) {
      socket.disconnect(); // Properly disconnect the socket
    }
    socket.dispose(); // Clean up resources
    _messageController.dispose(); // Dispose of the controller
    super.dispose();
  }

  String formatTime(String timestamp) {
    final dateTime = DateTime.parse(timestamp);
    return '${dateTime.hour}:${dateTime.minute}';
  }

  Future<void> _checkLoginStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token != null) {
      try {
        final response = await http.get(
          Uri.parse('http://localhost:5000/api/app/doctor'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          setState(() {
            _doctorId = data['user']['_id'] ?? _doctorId;
            fetchBookingDetails();
          });
        } else if (response.statusCode == 403) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } catch (e) {
        print("Error checking login status: $e");
      }
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // Fetch booking details
  Future<void> fetchBookingDetails() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    try {
      final response = await http.get(
        Uri.parse(
            'http://localhost:5000/api/app/bookingdetails/${widget.bookingId}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        //save user id to _userId
        setState(() {
          _userData = data;
        });
        _fetchMessages();
      } else {
        throw Exception('Failed to fetch booking details');
      }
    } catch (e) {
      print('Error fetching booking details: $e');
    }
  }

  void _connectSocket() {
    socket = IO.io(
      'http://localhost:5000',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect() // Auto-reconnect
          .setReconnectionAttempts(5) // Number of attempts
          .build(),
    );

    socket.onConnect((_) {
      print('Connected to WebSocket');
    });

    socket.onDisconnect((_) {
      print('Disconnected from WebSocket');
    });

    socket.onConnectError((error) {
      print('Connection Error: $error');
    });
  }

  Future<void> _sendMessage() async {
    String message = _messageController.text;
    if (message.isNotEmpty) {
      // Send message to API
      await _sendMessageToAPI(message);

      // Send message to Socket.IO server
      socket.emit('send_message', {
        'message': message,
        'isSender': true,
        'senderType': 'doctor',
        'timestamp': DateTime.now().toIso8601String(),
        'seen': false,
      });

      setState(() {
        messages.add({
          'message': message,
          'isSender': true,
          'senderType': 'doctor',
          'timestamp': 'Now',
          'seen': false,
        });
        _messageController.clear();
      });
    }
  }

  Future<void> _navigateToDynamicFrame() async {
    final patientInfo = {
      'name': _userData['booking']['patientName'],
      'age': _userData['booking']['patientAge'],
      'gender': _userData['booking']['patientGender'],
    };

    final imageBytes = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DynamicFramePage(patientInfo: patientInfo),
      ),
    );

    if (imageBytes != null) {
      await _sendImageToServer(imageBytes as Uint8List);
      setState(() {
        messages.add({
          'image': imageBytes,
          'isSender': true,
          'senderType': 'doctor',
          'timestamp': 'Now',
          'seen': false,
        });
      });
    }
  }

  Future<void> _sendImageToServer(Uint8List imageBytes) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');

    try {
      // Prepare the image file for upload
      final image = http.MultipartFile.fromBytes(
        'images', // The field name for the image in the form
        imageBytes,
        contentType:
            MediaType('image', 'jpeg'), // Adjust if necessary, e.g., 'png'
        filename: 'image.jpg', // Provide a filename if needed
      );

      // Prepare other fields for the form data
      final uri = Uri.parse('http://localhost:5000/api/message/sendmessage');
      final request = http.MultipartRequest('POST', uri)
        ..fields['message'] = '' // Sending an empty message
        ..fields['sender'] = _doctorId
        ..fields['bookingId'] = widget.bookingId
        ..fields['receiver'] = _userData['booking']['userId']['_id']
        ..fields['senderType'] = 'doctor'
        ..files.add(image); // Add the image file to the request

      // Add the authorization token to the headers if needed
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Send the request
      final response = await request.send();

      if (response.statusCode == 200) {
        print("Message sent successfully");
      } else {
        throw Exception('Failed to send message');
      }
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  Future<void> _fetchMessages() async {
    final String senderId =
        _userData['booking']['userId']['_id']; // Replace with actual sender ID
    final String receiverId = _doctorId; // Replace with actual receiver ID
    final String apiUrl =
        'http://localhost:5000/api/message/$senderId/$receiverId/${widget.bookingId}';

    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Fetched data: $data'); // Debugging print

        if (data is List) {
          // Ensure the data is a List
          setState(() {
            messages = data.map((message) {
              // Format the timestamp
              final originalTimestamp = message['timestamp'];
              final formattedTimestamp = DateFormat('yyyy-MM-dd hh:mm a')
                  .format(DateTime.parse(originalTimestamp));

              // Process images array and construct full URLs
              final images = (message['images'] as List<dynamic>?)
                  ?.map((image) => 'http://localhost:5000$image')
                  .toList();

              return {
                ...message,
                'time': formattedTimestamp,
                'images': images, // Attach processed image URLs
              };
            }).toList();
            isLoading = false;
          });
        } else {
          print('Unexpected data format: $data');
          setState(() {
            isLoading = false;
          });
        }
      } else {
        print('Failed to load messages');
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching messages: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _sendMessageToAPI(String message) async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:5000/api/message/sendmessage'),
        body: json.encode({
          'message': message,
          'sender': _doctorId,
          'bookingId': widget.bookingId,
          'receiver': _userData['booking']['userId']['_id'],
          'senderType': 'doctor'
        }),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode != 201) {
        print(response.statusCode);
        throw Exception('Failed to send message');
      }
      print("success sending message");
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  void _onTyping() {
    setState(() {
      _isTyping = _messageController.text.isNotEmpty;
    });
    socket.emit('typing', {'isTyping': _isTyping, 'sender': _doctorId});
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? Container(
            color: Colors.white, // Set the background color to white
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
        : Scaffold(
            appBar: AppBar(
              toolbarHeight: 100,
              title: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, '/profilesetting');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(0),
                      child: CircleAvatar(
                        radius: 25,
                        backgroundImage: _userData["booking"]["userId"]
                                    ["image"] ==
                                null
                            ? const AssetImage(
                                'assets/images/default_profile.png')
                            : NetworkImage(
                                'http://localhost:5000/uploads/${_userData["booking"]["userId"]["image"]}'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_userData['booking']['userId']['name']}',
                          style: const TextStyle(fontSize: 18)),
                      const Text("Online", style: TextStyle(fontSize: 14)),
                    ],
                  ),
                  const Spacer(),
                  Icon(Icons.videocam),
                  const SizedBox(width: 10),
                  Icon(Icons.phone),
                  const SizedBox(width: 10),
                  Icon(Icons.more_vert_rounded),
                  const SizedBox(width: 5),
                ],
              ),
            ),
            body: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Column(
                          children: [
                            // Patient information
                            Container(
                              padding: const EdgeInsets.only(
                                  top: 12, bottom: 20, left: 12, right: 12),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.5),
                                    spreadRadius: 1,
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  )
                                ],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              margin: const EdgeInsets.only(bottom: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(
                                    height: 10,
                                  ),
                                  const Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    child: Text(
                                      'Patient Information',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 10,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    child: Column(
                                      children: [
                                        Table(
                                          columnWidths: const {
                                            0: FlexColumnWidth(
                                                1), // First column takes 1x space
                                            1: FlexColumnWidth(
                                                2), // Second column takes 2x space
                                          },
                                          children: [
                                            _userData['booking']
                                                        ['patientName'] !=
                                                    null
                                                ? TableRow(
                                                    children: [
                                                      Text('Name'),
                                                      Text(
                                                        ': ${_userData['booking']['patientName']}',
                                                        style: TextStyle(
                                                            color: Color(
                                                                0xFF354044)),
                                                      ),
                                                    ],
                                                  )
                                                : TableRow(
                                                    children: [
                                                      SizedBox.shrink(),
                                                      SizedBox.shrink(),
                                                    ],
                                                  ),
                                            _userData['booking']
                                                        ['patientGender'] !=
                                                    null
                                                ? TableRow(
                                                    children: [
                                                      Text('Gender'),
                                                      Text(
                                                        ': ${_userData['booking']['patientGender']}',
                                                        style: TextStyle(
                                                            color: Color(
                                                                0xFF354044)),
                                                      ),
                                                    ],
                                                  )
                                                : TableRow(
                                                    children: [
                                                      SizedBox.shrink(),
                                                      SizedBox.shrink(),
                                                    ],
                                                  ),
                                            _userData['booking']
                                                        ['patientAge'] !=
                                                    null
                                                ? TableRow(
                                                    children: [
                                                      Text('Age'),
                                                      Text(
                                                        ': ${_userData['booking']['patientAge']}',
                                                        style: TextStyle(
                                                            color: Color(
                                                                0xFF354044)),
                                                      ),
                                                    ],
                                                  )
                                                : TableRow(
                                                    children: [
                                                      SizedBox.shrink(),
                                                      SizedBox.shrink(),
                                                    ],
                                                  ),
                                            _userData['booking']
                                                        ['patientWeight'] !=
                                                    null
                                                ? TableRow(
                                                    children: [
                                                      Text('Weight'),
                                                      Text(
                                                        ': ${_userData['booking']['patientWeight']}',
                                                        style: TextStyle(
                                                            color: Color(
                                                                0xFF354044)),
                                                      ),
                                                    ],
                                                  )
                                                : TableRow(
                                                    children: [
                                                      SizedBox.shrink(),
                                                      SizedBox.shrink(),
                                                    ],
                                                  ),
                                            _userData['booking']
                                                        ['problemDetails'] !=
                                                    null
                                                ? TableRow(
                                                    children: [
                                                      Text('Problem'),
                                                      Text(
                                                        ': ${_userData['booking']['problemDetails']}',
                                                        style: TextStyle(
                                                            color: Color(
                                                                0xFF354044)),
                                                      ),
                                                    ],
                                                  )
                                                : TableRow(
                                                    children: [
                                                      SizedBox.shrink(),
                                                      SizedBox.shrink(),
                                                    ],
                                                  ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.all(10.0),
                              child: Column(
                                children:
                                    List.generate(messages.length, (index) {
                                  final message = messages[index];
                                  final isLastReceiverMessage =
                                      _isLastInSequence(index);

                                  return Column(
                                    children: [
                                      _buildChatBubble(
                                        message['message'] ??
                                            '', // Use the correct key for the text content
                                        isSender:
                                            message['senderType'] == 'doctor' ??
                                                false, // Handle null values
                                        isLastReceiverMessage:
                                            isLastReceiverMessage,
                                        time: message['time'] ??
                                            'Now', // Ensure the correct key for time
                                        seen: message['seen'] ??
                                            false, // Provide a default for 'seen'
                                        image: message['image'] != null
                                            ? message['image'] as Uint8List
                                            : null,
                                        images: message['images'],
                                      ),
                                      SizedBox(height: 10),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                _buildMessageInput(),
              ],
            ),
          );
  }

  bool _isLastInSequence(int index) {
    if (index == messages.length - 1) return true;

    final bool currentIsSender = messages[index]['sender'] ==
        _doctorId; // Replace _currentUserId with the actual user ID
    final bool nextIsSender = messages[index + 1]['sender'] == _doctorId;

    return !currentIsSender && nextIsSender;
  }

  void _showImagePreview(BuildContext context,
      {Uint8List? memoryImage, String? networkImage}) {
    if (memoryImage == null && networkImage == null) return;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.black,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                memoryImage != null
                    ? Image.memory(
                        memoryImage,
                        fit: BoxFit.contain,
                      )
                    : Image.network(
                        networkImage!,
                        fit: BoxFit.contain,
                      ),
                SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    if (memoryImage != null) {
                      await _downloadImage(memoryImage);
                    } else if (networkImage != null) {
                      await _downloadImageFromNetwork(networkImage);
                    }
                  },
                  child: Text('Download Image'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

// Function to download image from memory (Uint8List)
  Future<void> _downloadImage(Uint8List memoryImage) async {
    // Request storage permission
    if (await Permission.storage.request().isGranted) {
      final directory = await getExternalStorageDirectory();
      final path =
          '${directory!.path}/image_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(memoryImage);

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Image downloaded to $path')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Permission Denied')));
    }
  }

// Function to download image from a network URL
  Future<void> _downloadImageFromNetwork(String imageUrl) async {
    try {
      final response = await HttpClient().getUrl(Uri.parse(imageUrl));
      final bytes = await response.close().then(
          (response) => response.fold<List<int>>([], (a, b) => a..addAll(b)));

      if (bytes.isNotEmpty) {
        await _downloadImage(Uint8List.fromList(bytes));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to download image')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error downloading image')));
    }
  }

  Widget _buildChatBubble(
    String message, {
    required bool isSender,
    bool isLastReceiverMessage = false,
    required String time,
    required bool seen,
    Uint8List? image,
    List<String>? images,
  }) {
    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Display multiple images from URLs
          if (images != null && images.isNotEmpty)
            ...images.map((imageUrl) {
              return GestureDetector(
                onTap: () => _showImagePreview(context, networkImage: imageUrl),
                child: Container(
                  width: 200,
                  height: 200,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            }).toList(),

          // Display single in-memory image
          if (image != null)
            GestureDetector(
              onTap: () => _showImagePreview(context, memoryImage: image),
              child: Container(
                width: 200,
                height: 200,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: MemoryImage(image),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          if (message != null && message != '')
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSender ? Colors.white : Color(0xFF0094FF),
                border: Border.all(color: Color(0xFFDADADA), width: 1),
                borderRadius: isSender
                    ? BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(4),
                      )
                    : isLastReceiverMessage
                        ? BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(4),
                            bottomRight: Radius.circular(16),
                          )
                        : BorderRadius.all(Radius.circular(16)),
              ),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  color: isSender ? Colors.black : Colors.white,
                ),
              ),
            ),
          SizedBox(height: 4),
          if (message != null && message != '' || image != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                if (!isSender)
                  Icon(
                    Icons.done_all,
                    size: 16,
                    color: seen ? Colors.blue : Colors.grey,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Row(
      children: [
        // Message input container
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: EdgeInsets.only(bottom: 20, left: 10),
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Color(0xFFDADADA), width: 1),
            ),
            child: Row(
              children: [
                // Text input field
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Color(0xFF979797)),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                    ),
                  ),
                ),
                // Attach and camera icons
                IconButton(
                  icon: Icon(Icons.attach_file),
                  onPressed: () {
                    // Handle file attachment
                  },
                ),
                IconButton(
                  icon: Icon(Icons.photo_camera),
                  onPressed: _navigateToDynamicFrame,
                ),
                // Send button (visible only when typing)
                if (_isTyping)
                  IconButton(
                    icon: Icon(Icons.send),
                    onPressed: _sendMessage,
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 10,
        ),
        // Mic button, positioned to the right of the input field
        Container(
          margin: EdgeInsets.only(right: 20, bottom: 20),
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Color(0xFF0094FF),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Color(0xFFDADADA), width: 1),
          ),
          child: IconButton(
            icon: Icon(Icons.mic, color: Colors.white),
            onPressed: () {
              // Handle audio recording
            },
          ),
        ),
      ],
    );
  }
}
