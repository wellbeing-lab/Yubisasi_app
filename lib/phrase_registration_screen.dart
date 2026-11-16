import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhraseRegistrationScreen extends StatefulWidget {
  const PhraseRegistrationScreen({super.key});

  @override
  State<PhraseRegistrationScreen> createState() => _PhraseRegistrationScreenState();
}

class _PhraseRegistrationScreenState extends State<PhraseRegistrationScreen> {
  final List<String> _categories = ['目的', '基本情報', '汎用', '症状', '痛みの種類'];
  String _selectedCategory = '目的';

  // 型推論をスッキリさせて文字化けを防いだデータ構造
  final Map<String, dynamic> _phraseData = {
  
    '目的': [
      {'text': '(診察券/保険証/医療証)を忘れました', 'isCustom': false},
      {'text': '(予約を取り/診察/予防接種/健康診断)に来ました', 'isCustom': false},
      {'text': '予約(あり/なし)です', 'isCustom': false},
      {'text': '初診です', 'isCustom': false},
    ],
    '基本情報': [
      {'text': 'アレルギーがあります', 'isCustom': false},
      {'text': '現在妊娠中です', 'isCustom': false},
    ],
    '汎用': [
      {'text': 'はい', 'isCustom': false},
      {'text': 'いいえ', 'isCustom': false},
    ],
    '症状': [
      {'text': '発熱があります', 'isCustom': false},
      {'text': '頭痛がします', 'isCustom': false},
    ],
    '痛みの種類': [
      {'text': 'ズキズキ痛む', 'isCustom': false},
      {'text': 'チクチク痛む', 'isCustom': false},
    ],
  };

  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomPhrases();
  }

  Future<void> _loadCustomPhrases() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('custom_phrases');
    if (savedData != null) {
      try {
        final decoded = jsonDecode(savedData) as Map<String, dynamic>;
        setState(() {
          decoded.forEach((category, list) {
            if (_phraseData.containsKey(category) && list is List) {
              for (var item in list) {
                if (item is Map && item['text'] != null) {
                  _phraseData[category]!.add({
                    'text': item['text'].toString(),
                    'isCustom': true,
                  });
                }
              }
            }
          });
        });
      } catch (e) {
        debugPrint('Error loading phrases: $e');
      }
    }
  }

  Future<void> _saveCustomPhrases() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> dataToSave = {};

    _phraseData.forEach((category, list) {
      final customOnly = list
          .where((item) => item['isCustom'] == true)
          .map((item) => {'text': item['text'].toString()})
          .toList();
      if (customOnly.isNotEmpty) {
        dataToSave[category] = customOnly;
      }
    });

    await prefs.setString('custom_phrases', jsonEncode(dataToSave));
  }

  void _addPhrase() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _phraseData[_selectedCategory]!.add({
        'text': text,
        'isCustom': true,
      });
      _inputController.clear();
    });

    _saveCustomPhrases();
  }

  void _showDeleteDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('この語句を削除しますか？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _phraseData[_selectedCategory]!.removeAt(index);
              });
              _saveCustomPhrases();
              Navigator.pop(context);
            },
            child: const Text('OK', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _phraseData[_selectedCategory] ?? [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '語句登録画面',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _categories.map((category) {
                final isSelected = category == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      category,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFF6FE19C),
                    backgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? Colors.transparent : Colors.grey.shade300,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = category;
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: currentList.length,
              itemBuilder: (context, index) {
                final item = currentList[index];
                final String text = item['text'] ?? '';
                final bool isCustom = item['isCustom'] == true;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (isCustom)
                        GestureDetector(
                          onTap: () => _showDeleteDialog(index),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: TextField(
                        controller: _inputController,
                        decoration: const InputDecoration(
                          hintText: '定型文を入力',
                          hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _addPhrase,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        side: const BorderSide(color: Colors.black, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('登録', style: TextStyle(fontWeight: FontWeight.bold)),
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
}