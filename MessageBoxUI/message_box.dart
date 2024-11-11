import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat UI Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MessageBoxPage(),
    );
  }
}

class MessageBoxPage extends StatefulWidget {
  const MessageBoxPage({super.key});

  @override
  _MessageBoxPageState createState() => _MessageBoxPageState();
}

class _MessageBoxPageState extends State<MessageBoxPage> {
  final List<Map<String, dynamic>> messages = [
    {
      'text': 'Hello James, welcome to my consult session.',
      'isSender': true,
      'time': '10:00 AM',
      'seen': true
    },
    {
      'text': 'I need assistance with my health reports.',
      'isSender': false,
      'time': '10:01 AM',
      'seen': true
    },
    {
      'text': 'Could you guide me through the steps?',
      'isSender': false,
      'time': '10:02 AM',
      'seen': true
    },
    {
      'text': 'Sure, let’s start with your latest test results.',
      'isSender': true,
      'time': '10:03 AM',
      'seen': false
    },
  ];

  final TextEditingController _messageController = TextEditingController();
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTyping);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTyping);
    _messageController.dispose();
    super.dispose();
  }

  void _onTyping() {
    setState(() {
      _isTyping = _messageController.text.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 100,
        title: Row(
          children: [
            const CircleAvatar(
            radius: 25,
            backgroundImage: NetworkImage('https://i.postimg.cc/3JNjLXLS/1725618700241.jpg'),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Smith Johnson', style: TextStyle(fontSize: 18)),
                const Text("Online", style: TextStyle(fontSize: 14)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.videocam),
            const SizedBox(width: 10),
            const Icon(Icons.phone),
            const SizedBox(width: 10),
            const Icon(Icons.more_vert_rounded),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isLastReceiverMessage = _isLastInSequence(index);
                return Column(
                  children: [
                    _buildChatBubble(
                      message['text'],
                      isSender: message['isSender'],
                      isLastReceiverMessage: isLastReceiverMessage,
                      time: message['time'],
                      seen: message['seen'],
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  bool _isLastInSequence(int index) {
    if (index == messages.length - 1) return true;
    return !messages[index]['isSender'] && messages[index + 1]['isSender'];
  }

  Widget _buildChatBubble(String message,
      {required bool isSender,
      bool isLastReceiverMessage = false,
      required String time,
      required bool seen}) {
    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSender ? Colors.white : const Color(0xFF0094FF),
              borderRadius: isSender
                  ? BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    )
                  : isLastReceiverMessage
                      ? BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        )
                      : BorderRadius.circular(16),
            ),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: isSender ? Colors.black : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: const TextStyle(
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
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(bottom: 20, left: 10),
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.photo_camera),
                  onPressed: () {},
                ),
                if (_isTyping)
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      if (_messageController.text.isNotEmpty) {
                        setState(() {
                          messages.add({
                            'text': _messageController.text,
                            'isSender': true,
                            'time': 'Now',
                            'seen': false,
                          });
                          _messageController.clear();
                        });
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(right: 20, bottom: 20),
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFF0094FF),
            borderRadius: BorderRadius.circular(25),
          ),
          child: IconButton(
            icon: const Icon(Icons.mic, color: Colors.white),
            onPressed: () {},
          ),
        ),
      ],
    );
  }
}
