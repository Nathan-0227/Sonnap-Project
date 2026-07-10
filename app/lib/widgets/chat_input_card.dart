import 'package:flutter/material.dart';

class ChatInputCard extends StatefulWidget {
  final ValueChanged<String> onSend;
  final VoidCallback onHistory;

  const ChatInputCard({
    super.key,
    required this.onSend,
    required this.onHistory,
  });

  @override
  State<ChatInputCard> createState() => _ChatInputCardState();
}

class _ChatInputCardState extends State<ChatInputCard> {
  final TextEditingController _controller = TextEditingController();

  void _sendQuestion() {
    final question = _controller.text.trim();

    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a question."),
        ),
      );
      return;
    }

    widget.onSend(question);
    _controller.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Ask Sonnap",
              hintStyle: const TextStyle(
                color: Colors.white54,
              ),
              filled: true,
              fillColor: const Color(0xFF1B2F63),
              contentPadding: const EdgeInsets.all(18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onHistory,
                  icon: const Icon(Icons.history),
                  label: const Text("History"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF223A73),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              SizedBox(
                width: 70,
                height: 52,
                child: ElevatedButton(
                  onPressed: _sendQuestion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C6DFF),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}