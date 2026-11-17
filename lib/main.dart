import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String modelId = 'sugarcane-leaf-diseases/2';
const String inferenceUrl = 'https://serverless.roboflow.com/$modelId';
const Color leafGreen = Color(0xFF246B45);
const Color paleGreen = Color(0xFFEAF4EC);

void main() => runApp(const SugarLeafApp());

class SugarLeafApp extends StatelessWidget {
  const SugarLeafApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SugarLeaf AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: leafGreen, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7FAF7),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7FAF7), foregroundColor: Color(0xFF183B2A)),
        cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      ),
      home: const HomeScreen(),
    );
  }
}

class Prediction {
  final String label;
  final double confidence;
  final double x, y, width, height;
  Prediction({required this.label, required this.confidence, required this.x, required this.y, required this.width, required this.height});

  factory Prediction.fromJson(Map<String, dynamic> json) => Prediction(
    label: (json['class'] ?? json['class_name'] ?? 'Unknown').toString(),
    confidence: (json['confidence'] as num? ?? 0).toDouble(),
    x: (json['x'] as num? ?? 0).toDouble(),
    y: (json['y'] as num? ?? 0).toDouble(),
    width: (json['width'] as num? ?? 0).toDouble(),
    height: (json['height'] as num? ?? 0).toDouble(),
  );
}

class ScanRecord {
  final String label;
  final double confidence;
  final DateTime date;
  ScanRecord(this.label, this.confidence, this.date);
  Map<String, dynamic> toJson() => {'label': label, 'confidence': confidence, 'date': date.toIso8601String()};
  factory ScanRecord.fromJson(Map<String, dynamic> j) => ScanRecord(j['label'], (j['confidence'] as num).toDouble(), DateTime.parse(j['date']));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker picker = ImagePicker();
  File? selectedImage;
  List<Prediction> predictions = [];
  List<ScanRecord> history = [];
  bool loading = false;
  String? error;
  String? imageDimensions;
  double? _imageWidth;
  double? _imageHeight;
  double confidenceThreshold = 0.25;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('scan_history');
    if (raw == null) return;
    try {
      final items = (jsonDecode(raw) as List).map((e) => ScanRecord.fromJson(Map<String, dynamic>.from(e))).toList();
      if (mounted) setState(() => history = items);
    } catch (_) {}
  }

  Future<void> _saveHistory(String label, double confidence) async {
    history.insert(0, ScanRecord(label, confidence, DateTime.now()));
    if (history.length > 30) history = history.take(30).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('scan_history', jsonEncode(history.map((e) => e.toJson()).toList()));
  }

  Future<void> _choose(ImageSource source) async {
    try {
      final XFile? file = await picker.pickImage(source: source, imageQuality: 92, maxWidth: 1800);
      if (file == null) return;
      setState(() {
        selectedImage = File(file.path);
        predictions = [];
        error = null;
        imageDimensions = null;
        _imageWidth = null;
        _imageHeight = null;
      });
    } catch (e) {
      setState(() => error = 'Unable to open image: $e');
    }
  }

  Future<void> _detect() async {
    if (selectedImage == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('roboflow_api_key')?.trim() ?? '';
    if (key.isEmpty) {
      _message('Add your Roboflow API key in Settings first.');
      return;
    }
    setState(() { loading = true; error = null; predictions = []; });
    try {
      final bytes = await selectedImage!.readAsBytes();
      final encoded = base64Encode(bytes);
      final response = await http.post(
        Uri.parse(inferenceUrl),
        headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/x-www-form-urlencoded'},
        body: encoded,
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Roboflow returned HTTP ${response.statusCode}: ${_short(response.body)}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (data['predictions'] as List? ?? []);
      final found = raw.map((e) => Prediction.fromJson(Map<String, dynamic>.from(e)))
          .where((p) => p.confidence >= confidenceThreshold).toList()
        ..sort((a,b) => b.confidence.compareTo(a.confidence));
      final width = (data['image']?['width'] as num?)?.toInt();
      final height = (data['image']?['height'] as num?)?.toInt();
      final top = found.isNotEmpty ? found.first : null;
      if (top != null) await _saveHistory(top.label, top.confidence);
      if (!mounted) return;
      setState(() {
        predictions = found;
        imageDimensions = width != null && height != null ? '$width × $height px' : null;
        _imageWidth = width?.toDouble();
        _imageHeight = height?.toDouble();
      });
      if (found.isEmpty) _message('No confident leaf disease detection. Try a clearer, closer photo.');
    } on TimeoutException {
      setState(() => error = 'The request timed out. Check your internet connection and try again.');
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _short(String s) => s.length > 260 ? '${s.substring(0,260)}…' : s;
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _pretty(String s) => s.replaceAll('-', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  @override
  Widget build(BuildContext context) {
    final top = predictions.isEmpty ? null : predictions.first;
    final categoryCounts = <String, int>{
      'Healthy': 0,
      'Banded': 0,
      'Brown-Spot': 0,
      'Dried': 0,
      'Other': 0,
    };
    for (final prediction in predictions) {
      final name = prediction.label.toLowerCase().replaceAll('_', '-').trim();
      if (name == 'healthy') {
        categoryCounts['Healthy'] = categoryCounts['Healthy']! + 1;
      } else if (name.contains('banded')) {
        categoryCounts['Banded'] = categoryCounts['Banded']! + 1;
      } else if (name.contains('brown')) {
        categoryCounts['Brown-Spot'] = categoryCounts['Brown-Spot']! + 1;
      } else if (name == 'dried' || name.contains('dry')) {
        categoryCounts['Dried'] = categoryCounts['Dried']! + 1;
      } else {
        categoryCounts['Other'] = categoryCounts['Other']! + 1;
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(children: const [
          Icon(Icons.eco, color: leafGreen, size: 27),
          SizedBox(width: 8),
          Text('SugarLeaf AI', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [IconButton(tooltip: 'Settings', onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        }, icon: const Icon(Icons.settings_outlined))],
      ),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: leafGreen, borderRadius: BorderRadius.circular(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('Know your crop.\\nProtect your harvest.', style: TextStyle(color: Colors.white, fontSize: 23, height: 1.18, fontWeight: FontWeight.w800)),
              SizedBox(height: 9),
              Text('AI-assisted sugarcane leaf screening', style: TextStyle(color: Color(0xFFDCEFE1), fontSize: 13)),
              SizedBox(height: 14),
              Row(children: [Icon(Icons.cloud_done_outlined, color: Colors.white70, size: 16), SizedBox(width: 6), Text('Powered by Roboflow hosted YOLOv11', style: TextStyle(color: Colors.white70, fontSize: 11))]),
            ]),
          ),
          const SizedBox(height: 22),
          const SectionHeading('Leaf image', subtitle: 'Capture a clear photo or choose one from your gallery.'),
          const SizedBox(height: 12),
          if (selectedImage == null)
            InkWell(
              onTap: () => _choose(ImageSource.gallery),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                height: 230,
                decoration: BoxDecoration(color: paleGreen, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFC9DDCE), style: BorderStyle.solid)),
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircleAvatar(radius: 31, backgroundColor: Colors.white, child: Icon(Icons.add_a_photo_outlined, color: leafGreen, size: 30)),
                  SizedBox(height: 12),
                  Text('Add a sugarcane leaf photo', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF214C33))),
                  SizedBox(height: 5),
                  Text('JPG or PNG · close, well-lit image', style: TextStyle(color: Colors.black54, fontSize: 12)),
                ]),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                color: Colors.black,
                constraints: const BoxConstraints(maxHeight: 310),
                child: Stack(fit: StackFit.passthrough, children: [
                  Image.file(selectedImage!, fit: BoxFit.contain, height: 300, width: double.infinity),
                  if (predictions.isNotEmpty)
                    Positioned.fill(child: CustomPaint(painter: DetectionPainter(predictions, imageWidth: _imageWidth, imageHeight: _imageHeight))),
                  Positioned(right: 10, top: 10, child: IconButton.filledTonal(onPressed: () => setState(() { selectedImage = null; predictions = []; error = null; }), icon: const Icon(Icons.close))),
                ]),
              ),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: loading ? null : () => _choose(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: loading ? null : () => _choose(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery'))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Expanded(child: Text('Minimum confidence', style: TextStyle(fontSize: 12, color: Colors.black54))),
            Text('${(confidenceThreshold*100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700, color: leafGreen)),
          ]),
          Slider(value: confidenceThreshold, min: 0.1, max: 0.8, divisions: 14, onChanged: (v) => setState(() => confidenceThreshold = v)),
          FilledButton.icon(
            onPressed: selectedImage == null || loading ? null : _detect,
            icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.document_scanner_outlined),
            label: Text(loading ? 'Analyzing leaf…' : 'Detect disease'),
            style: FilledButton.styleFrom(backgroundColor: leafGreen, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(14)), child: Text(error!, style: const TextStyle(color: Color(0xFF9C2525), fontSize: 12))),
          ],
          if (predictions.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionHeading('Detection results', subtitle: 'Model predictions above the selected confidence threshold.'),
            const SizedBox(height: 10),
            if (top != null) _MainResult(label: _pretty(top.label), confidence: top.confidence),
            const SizedBox(height: 12),
            _CategorySummary(counts: categoryCounts),
            const SizedBox(height: 12),
            const SectionHeading('Individual detections', subtitle: 'Each bounding box returned by YOLOv11 is counted as one detection.'),
            const SizedBox(height: 8),
            ...predictions.map((p) => Card(child: ListTile(
              leading: const CircleAvatar(backgroundColor: paleGreen, child: Icon(Icons.spa_outlined, color: leafGreen)),
              title: Text(_pretty(p.label), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Bounding box · ${p.width.toStringAsFixed(0)} × ${p.height.toStringAsFixed(0)} px'),
              trailing: Text('${(p.confidence*100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w800, color: leafGreen)),
            ))),
            if (imageDimensions != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text('Image size: $imageDimensions', style: const TextStyle(color: Colors.black45, fontSize: 11))),
            const SizedBox(height: 12),
            _AdviceCard(label: top?.label ?? ''),
          ],
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const SectionHeading('Recent scans'),
            TextButton(onPressed: history.isEmpty ? null : () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('scan_history');
              setState(() => history = []);
            }, child: const Text('Clear')),
          ]),
          if (history.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Your recent detections will appear here.', style: TextStyle(color: Colors.black45, fontSize: 12)))
          else
            ...history.take(5).map((h) => Card(child: ListTile(
              dense: true,
              leading: const Icon(Icons.history, color: leafGreen),
              title: Text(_pretty(h.label), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${h.date.toLocal()}'.split('.').first),
              trailing: Text('${(h.confidence*100).toStringAsFixed(1)}%'),
            ))),
          const SizedBox(height: 20),
          const Text('For preliminary screening only. Confirm suspected disease with a qualified agriculturist or plant pathologist before treatment decisions.', style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4)),
        ],
      )),
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionHeading(this.title, {this.subtitle, super.key});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF203B2B))),
    if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(subtitle!, style: const TextStyle(fontSize: 12, color: Colors.black54))),
  ]);
}


class _CategorySummary extends StatelessWidget {
  final Map<String, int> counts;
  const _CategorySummary({required this.counts});

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    final visibleCounts = counts.entries.where((entry) => entry.key != 'Other' || entry.value > 0).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Disease category summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: paleGreen, borderRadius: BorderRadius.circular(12)),
              child: Text('$total total', style: const TextStyle(color: leafGreen, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 5),
          const Text('Number of detected regions grouped by predicted class', style: TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 14),
          ...visibleCounts.map((entry) {
            final fraction = total == 0 ? 0.0 : entry.value / total;
            final percent = total == 0 ? 0 : (fraction * 100).round();
            return Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  Text('${entry.value}', style: const TextStyle(fontWeight: FontWeight.w800, color: leafGreen)),
                  const SizedBox(width: 8),
                  SizedBox(width: 44, child: Text('$percent%', textAlign: TextAlign.end, style: const TextStyle(fontSize: 11, color: Colors.black54))),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 9,
                    backgroundColor: const Color(0xFFE8EEE9),
                    valueColor: const AlwaysStoppedAnimation<Color>(leafGreen),
                  ),
                ),
              ]),
            );
          }),
          if (total == 0)
            const Text('No detections above the selected confidence threshold.', style: TextStyle(color: Colors.black54, fontSize: 12)),
          const Divider(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total detected regions', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('$total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: leafGreen)),
          ]),
        ]),
      ),
    );
  }
}

class _MainResult extends StatelessWidget {
  final String label; final double confidence;
  const _MainResult({required this.label, required this.confidence});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(color: paleGreen, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFD2E5D6))),
    child: Row(children: [
      const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.eco, color: leafGreen)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Top detected class', style: TextStyle(fontSize: 11, color: Colors.black54)),
        Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: leafGreen)),
      ])),
      Text('${(confidence*100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: leafGreen)),
    ]),
  );
}

class _AdviceCard extends StatelessWidget {
  final String label;
  const _AdviceCard({required this.label});
  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase();
    String title, advice;
    if (normalized == 'healthy') {
      title = 'Healthy-class prediction';
      advice = 'The model classified the visible leaf as Healthy. Continue routine field scouting and monitor other plants; this result does not guarantee the whole plant or field is disease-free.';
    } else if (normalized.contains('banded')) {
      title = 'Banded-class prediction';
      advice = 'Inspect the whole plant and nearby stools for similar banding symptoms. Photograph several leaves and seek confirmation from an agricultural extension officer before applying control measures.';
    } else if (normalized.contains('brown')) {
      title = 'Brown-Spot-class prediction';
      advice = 'Check whether spots are spreading across older and younger leaves. Record affected locations and obtain expert confirmation; avoid choosing fungicides based only on this model output.';
    } else if (normalized.contains('dried')) {
      title = 'Dried-class prediction';
      advice = 'Drying can have several causes, including water stress, nutrient issues, pests, or disease. Check soil moisture, drainage, plant condition, and nearby symptoms before deciding on management.';
    } else {
      title = 'Field inspection recommended';
      advice = 'The detected class needs further inspection. Capture additional well-lit images and consult a qualified agriculturist or plant pathologist.';
    }
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.lightbulb_outline, color: leafGreen), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)))]),
      const SizedBox(height: 8), Text(advice, style: const TextStyle(fontSize: 12, height: 1.45, color: Colors.black87)),
    ])));
  }
}

class DetectionPainter extends CustomPainter {
  final List<Prediction> predictions;
  final double? imageWidth, imageHeight;
  DetectionPainter(this.predictions, {this.imageWidth, this.imageHeight});
  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth == null || imageHeight == null || imageWidth! <= 0 || imageHeight! <= 0) return;
    final fitted = applyBoxFit(BoxFit.contain, Size(imageWidth!, imageHeight!), size);
    final scale = fitted.destination.width / imageWidth!;
    final dx = (size.width - fitted.destination.width) / 2;
    final dy = (size.height - fitted.destination.height) / 2;
    final paint = Paint()..color = const Color(0xFF21D07A)..style = PaintingStyle.stroke..strokeWidth = 2.5;
    final fill = Paint()..color = const Color(0xAA145C38);
    for (final p in predictions) {
      final rect = Rect.fromCenter(
        center: Offset(dx + p.x * scale, dy + p.y * scale),
        width: p.width * scale,
        height: p.height * scale,
      );
      canvas.drawRect(rect, paint);
      final label = '${p.label} ${(p.confidence*100).toStringAsFixed(0)}%';
      final tp = TextPainter(text: TextSpan(text: label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout(maxWidth: math.max(80, rect.width));
      final tag = Rect.fromLTWH(rect.left, math.max(0, rect.top - tp.height - 7), tp.width + 10, tp.height + 6);
      canvas.drawRect(tag, fill);
      tp.paint(canvas, Offset(tag.left + 5, tag.top + 3));
    }
  }
  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) =>
      oldDelegate.predictions != predictions || oldDelegate.imageWidth != imageWidth || oldDelegate.imageHeight != imageHeight;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  final controller = TextEditingController();
  bool obscure = true;
  bool saved = false;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      controller.text = p.getString('roboflow_api_key') ?? '';
      if (mounted) setState(() {});
    });
  }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('roboflow_api_key', controller.text.trim());
    if (mounted) setState(() => saved = true);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Roboflow API key', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      const SizedBox(height: 8),
      const Text('Paste your private Roboflow API key. It is not included in the source code.', style: TextStyle(color: Colors.black54, height: 1.4)),
      const SizedBox(height: 16),
      TextField(controller: controller, obscureText: obscure, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(
        labelText: 'API key', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => obscure = !obscure)),
      )),
      const SizedBox(height: 14),
      FilledButton(onPressed: _save, child: const Text('Save API key')),
      if (saved) const Padding(padding: EdgeInsets.only(top: 10), child: Text('API key saved on this device.', style: TextStyle(color: leafGreen))),
      const SizedBox(height: 26),
      const Text('Model details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 8),
      const SelectableText('Model ID: $modelId\\nEndpoint: $inferenceUrl\\nClasses: Healthy, Banded, Brown-Spot, Dried'),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFFFF4DF), borderRadius: BorderRadius.circular(14)), child: const Text('Security: this starter app stores the key in local app preferences. Do not publish or distribute this build with a real key. For production, proxy requests through an authenticated backend and use secure secret management.', style: TextStyle(fontSize: 12, height: 1.4))),
    ]),
  );
}
