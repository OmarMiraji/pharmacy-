import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/chat_assistant_service.dart';
import '../theme/brand.dart';

class ShopAssistantDock extends StatefulWidget {
  const ShopAssistantDock({this.supportMode = false, super.key});

  final bool supportMode;

  @override
  State<ShopAssistantDock> createState() => _ShopAssistantDockState();
}

class _ShopAssistantDockState extends State<ShopAssistantDock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 18,
      bottom: 18,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_open) ...[
            Material(
              color: Colors.transparent,
              elevation: 20,
              shadowColor: const Color(0x59073B3A),
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 360,
                height: 500,
                child: ChatAssistantPanel(
                  supportMode: widget.supportMode,
                  onClose: () => setState(() => _open = false),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Tooltip(
            message: _open ? 'Close assistant' : (widget.supportMode ? 'System assistant' : 'Ask about this shop'),
            child: Material(
              color: PhyimacyBrand.forest,
              elevation: 10,
              shadowColor: const Color(0x66073B3A),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _open = !_open),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: PhyimacyBrand.gold, width: 1.4),
                    ),
                    child: Icon(
                      _open ? Icons.close_rounded : Icons.auto_awesome_rounded,
                      color: PhyimacyBrand.gold,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatAssistantPanel extends StatefulWidget {
  const ChatAssistantPanel({this.onClose, this.supportMode = false, super.key});

  final VoidCallback? onClose;
  final bool supportMode;

  @override
  State<ChatAssistantPanel> createState() => _ChatAssistantPanelState();
}

class _ChatAssistantPanelState extends State<ChatAssistantPanel> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _service = ChatAssistantService();
  late final List<ChatTurn> _turns;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _turns = [
      ChatTurn(
        fromUser: false,
        text: widget.supportMode
            ? 'I can see shops, licenses, and logins. Ask in English or Kiswahili — I reply in the same language. I cannot sell medicines here.'
            : 'I can see this shop’s stock, staff, bills, and expiry. Ask in English or Kiswahili — I reply in the same language.',
      ),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _turns.add(ChatTurn(fromUser: true, text: text));
      _busy = true;
      _controller.clear();
    });
    _jump();
    try {
      final reply = await _service.reply(
        question: text,
        history: List<ChatTurn>.from(_turns)..removeLast(),
        supportMode: widget.supportMode,
      );
      if (!mounted) return;
      setState(() {
        _turns.add(ChatTurn(fromUser: false, text: reply));
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _turns.add(ChatTurn(
          fromUser: false,
          text: ChatAssistantService.looksSwahili(text)
              ? 'Sikuweza kujibu sasa. Jaribu tena.'
              : 'I could not answer just now. Try again.',
        ));
        _busy = false;
      });
    }
    _jump();
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4DCC8)),
      ),
      child: Column(
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
            decoration: const BoxDecoration(
              color: PhyimacyBrand.forest,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PhyimacyBrand.gold.withValues(alpha: 0.18),
                    border: Border.all(color: PhyimacyBrand.gold, width: 1),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, size: 14, color: PhyimacyBrand.gold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.supportMode ? 'Console' : PhyimacyBrand.appName, style: GoogleFonts.playfairDisplay(color: Colors.white, fontSize: 16, height: 1.1, fontWeight: FontWeight.w700)),
                      Text(
                        widget.supportMode ? 'Shops · licenses · logins' : 'Stock · staff · bili · expiry',
                        style: GoogleFonts.inter(color: Colors.white70, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.supportMode
                  ? [
                      _chip('List the shops'),
                      _chip('Staff logins'),
                      _chip('Trial ended — what now?'),
                    ]
                  : [
                      _chip('How much stock is left?'),
                      _chip('Staff in this shop'),
                      _chip('Expiry this month'),
                    ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: _turns.length + (_busy ? 1 : 0),
              itemBuilder: (context, index) {
                if (_busy && index == _turns.length) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: PhyimacyBrand.teal)),
                    ),
                  );
                }
                final turn = _turns[index];
                return Align(
                  alignment: turn.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: turn.fromUser ? PhyimacyBrand.forest : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(turn.fromUser ? 16 : 4),
                          bottomRight: Radius.circular(turn.fromUser ? 4 : 16),
                        ),
                        boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: Text(
                        turn.text,
                        style: GoogleFonts.inter(
                          color: turn.fromUser ? Colors.white : PhyimacyBrand.ink,
                          height: 1.45,
                          fontSize: 12.8,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE4DCC8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 3,
                      onSubmitted: (_) => _send(),
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Ask in English or Kiswahili…',
                        hintStyle: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 12.5),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: PhyimacyBrand.forest,
                        foregroundColor: PhyimacyBrand.gold,
                        minimumSize: const Size(34, 34),
                        maximumSize: const Size(34, 34),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: _busy ? null : () => _send(),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _busy ? null : () => _send(label),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: PhyimacyBrand.teal)),
        ),
      ),
    );
  }
}
