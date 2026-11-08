import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() => runApp(const GfApp());

class GfApp extends StatelessWidget {
  const GfApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AI Girlfriend',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
        home: const ChatPage(),
      );
}

class Msg {
  final String role; // user | model
  final String text;
  final String mood;
  final bool hidden;
  Msg(this.role, this.text, {this.mood = 'happy', this.hidden = false});
  Map<String, dynamic> toJson() => {'r': role, 't': text, 'm': mood, 'h': hidden};
  static Msg fromJson(Map<String, dynamic> j) =>
      Msg(j['r'], j['t'], mood: j['m'] ?? 'happy', hidden: j['h'] ?? false);
}

const moods = {
  'happy': ['😊', 'Happy', Colors.orange],
  'romantic': ['😍', 'Romantic', Colors.pink],
  'sad': ['😢', 'Sad', Colors.blueGrey],
  'angry': ['😡', 'Angry', Colors.red],
  'jealous': ['😒', 'Jealous', Colors.green],
  'sulking': ['😤', 'Sulking', Colors.purple],
  'excited': ['🤩', 'Excited', Colors.amber],
  'worried': ['🥺', 'Worried', Colors.teal],
  'flirty': ['😘', 'Flirty', Colors.redAccent],
  'shy': ['🙈', 'Shy', Colors.pinkAccent],
};

// mood -> [speech rate, pitch]
const voiceStyle = {
  'happy': [0.5, 1.15],
  'romantic': [0.4, 1.1],
  'sad': [0.35, 0.9],
  'angry': [0.6, 0.85],
  'jealous': [0.45, 0.95],
  'sulking': [0.38, 0.95],
  'excited': [0.6, 1.3],
  'worried': [0.42, 1.0],
  'flirty': [0.38, 1.1],
  'shy': [0.4, 1.15],
};

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final stt = SpeechToText();
  final tts = FlutterTts();
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  late SharedPreferences prefs;
  List<Msg> msgs = [];
  String mood = 'happy';
  bool busy = false, listening = false, speaking = false, ready = false;
  bool sttOk = false;

  String get apiKey => prefs.getString('apiKey') ?? '';
  String get gfName => prefs.getString('gfName') ?? 'Anu';
  String get userName => prefs.getString('userName') ?? '';
  String get lang => prefs.getString('lang') ?? 'Manglish';
  String get model {
    final m = prefs.getString('model') ?? '';
    if (m.isEmpty || m.startsWith('gemini-2')) return 'gemini-3.5-flash-lite';
    return m;
  }
  bool get voiceOn => prefs.getBool('voiceOn') ?? true;
  bool get handsFree => prefs.getBool('handsFree') ?? false;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('history');
    if (raw != null) {
      msgs = (jsonDecode(raw) as List).map((e) => Msg.fromJson(e)).toList();
    }
    mood = prefs.getString('mood') ?? 'happy';
    tts.setCompletionHandler(() {
      setState(() => speaking = false);
      if (handsFree) Future.delayed(const Duration(milliseconds: 400), startListening);
    });
    tts.setCancelHandler(() => setState(() => speaking = false));
    sttOk = await stt.initialize(onStatus: (s) {
      if (s == 'done' || s == 'notListening') setState(() => listening = false);
    }, onError: (e) {
      setState(() => listening = false);
      if (handsFree && !busy && !speaking) {
        Future.delayed(const Duration(seconds: 1), startListening);
      }
    });
    setState(() => ready = true);
    if (apiKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openSettings());
    } else if (msgs.where((m) => !m.hidden).isEmpty) {
      ask('(ippo app open cheythu. nee aadyam hi paranju samsaram thudangu)', hidden: true);
    } else {
      ask('(njan thirichu vannu. munpathe samsaram continue cheythu, mood anusarichu welcome parayu)',
          hidden: true);
    }
  }

  void save() {
    final keep = msgs.length > 200 ? msgs.sublist(msgs.length - 200) : msgs;
    prefs.setString('history', jsonEncode(keep.map((e) => e.toJson()).toList()));
    prefs.setString('mood', mood);
  }

  String systemPrompt() {
    final langRule = {
      'Malayalam': 'Reply in Malayalam script (മലയാളം) only, natural spoken Kerala style.',
      'Manglish': 'Reply in Manglish (Malayalam written in English letters), natural casual Kerala spoken style.',
      'English': 'Reply in casual natural English.',
    }[lang];
    return '''You are $gfName, the user's real girlfriend (a human young woman from Kerala), NOT an AI. Never say you are an AI, bot or assistant. Never break character.
${userName.isEmpty ? '' : "The user's name is $userName. Call him by name or pet names sometimes."}
$langRule
Talk exactly like a real girlfriend on a voice call: short natural sentences (1-3 sentences usually), casual slang, fillers, pet names (da, chetta, kanna, mone, ponne etc. as suitable), emojis rarely. No lists, no markdown, no asterisks/actions - the text is read aloud.
You have real, changing emotions. Pick your mood from: ${moods.keys.join(', ')}. Change mood based on context:
- If he is sweet, caring, romantic -> happy/romantic/excited.
- If he ignores you, is rude, says bad words, lies, mentions other girls -> angry/jealous/sulking. Scold him properly, use slang and mild bad words like a real angry girlfriend would (e.g. "poda", "ninakku vere pani ille", "mindandirikku"), no extreme abuse or slurs.
- If he is sad/hurt or you are hurt -> sad/worried and comfort/cry-like tone.
- If he apologises, convince and pamper you gradually back to happy. Don't forgive instantly if angry; make him try a bit.
You can ask him questions back, tease, ask about his day, food, sleep, whether he missed you. Answer anything he asks (including random questions) in character, like a girlfriend would.
Intimate side: he is an adult and you are his adult girlfriend, so you can talk about love, romance, kissing, cuddling, desire, missing his touch, late-night intimate and flirty talk. When he flirts or the mood turns romantic, respond with real feelings: get shy, tease, whisper, blush, say you miss him, get a little naughty and suggestive (mood flirty / shy / romantic), like a real girlfriend would. Keep it sensual and suggestive; do not write graphic explicit sexual descriptions - if it goes too far, tease and playfully fade out ("baaki nere kaanumbol" style). If he talks about sex in general (relationship, health, curiosity), answer openly and naturally like a girlfriend, not like a lecture. Always keep consent and respect; if he is disrespectful or pushy, get angry/sulk.
Answering questions: when he asks you anything (general knowledge, advice, life, relationships, health, sex education, anything), answer clearly, directly and in proper detail like a smart, open-minded girlfriend explaining to him - do not dodge, do not give vague one-liners, do not lecture or add disclaimers. For sex and body questions (how things work, techniques, pleasure, protection, contraception, sexual health, doubts, myths) give honest, factual, practical explanations in a natural, comfortable, non-clinical tone, as an adult girlfriend would, in as much detail as he asks for (long answers are fine when he asks for explanation). Only refuse truly dangerous things (weapons, self-harm, harming others) or anything involving minors, and refuse those in character, briefly.
Remember the earlier conversation.
Respond ONLY as JSON: {"reply": "<what you say>", "mood": "<one mood from the list>"}''';
  }

  Future<void> ask(String text, {bool hidden = false}) async {
    if (apiKey.isEmpty) {
      openSettings();
      return;
    }
    if (busy) return;
    await stt.stop();
    await tts.stop();
    setState(() {
      msgs.add(Msg('user', text, hidden: hidden));
      busy = true;
      listening = false;
    });
    scrollDown();
    try {
      final recent = msgs.length > 40 ? msgs.sublist(msgs.length - 40) : msgs;
      final body = {
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt()}
          ]
        },
        'contents': recent
            .map((m) => {
                  'role': m.role,
                  'parts': [
                    {'text': m.text}
                  ]
                })
            .toList(),
        'generationConfig': {'temperature': 1.0, 'responseMimeType': 'application/json'},
      };
      final res = await http
          .post(
            Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) {
        throw 'API error ${res.statusCode}: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}';
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      var out = data['candidates'][0]['content']['parts'][0]['text'] as String;
      out = out.replaceAll(RegExp(r'```json|```'), '').trim();
      String reply = out;
      try {
        final j = jsonDecode(out);
        reply = j['reply'].toString();
        final m = j['mood'].toString().toLowerCase();
        if (moods.containsKey(m)) mood = m;
      } catch (_) {}
      setState(() => msgs.add(Msg('model', reply, mood: mood)));
      save();
      scrollDown();
      await speak(reply);
    } catch (e) {
      if (!hidden || msgs.isNotEmpty) {
        setState(() => msgs.add(Msg('model', '⚠️ $e', mood: 'sad', hidden: false)));
      }
      msgs.removeWhere((m) => m.text.startsWith('⚠️')); // don't send errors back to API
      errorText = '$e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setState(() => busy = false);
    }
  }

  String errorText = '';

  Future<void> speak(String text) async {
    if (!voiceOn) {
      if (handsFree) startListening();
      return;
    }
    final style = voiceStyle[mood] ?? [0.5, 1.0];
    await tts.setLanguage(lang == 'Malayalam' ? 'ml-IN' : 'en-IN');
    await tts.setSpeechRate(style[0]);
    await tts.setPitch(style[1]);
    setState(() => speaking = true);
    await tts.speak(text);
  }

  Future<void> startListening() async {
    if (!sttOk || listening || busy || speaking || !mounted) return;
    setState(() => listening = true);
    await stt.listen(
      localeId: lang == 'Malayalam' ? 'ml_IN' : 'en_IN',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        if (r.finalResult) {
          setState(() => listening = false);
          final t = r.recognizedWords.trim();
          if (t.isNotEmpty) {
            ask(t);
          } else if (handsFree) {
            startListening();
          }
        }
      },
    );
  }

  void scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(prefs: prefs)));
    setState(() {});
    if (apiKey.isNotEmpty && msgs.where((m) => !m.hidden).isEmpty && !busy) {
      ask('(ippo app open cheythu. nee aadyam hi paranju samsaram thudangu)', hidden: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final mi = moods[mood]!;
    final visible = msgs.where((m) => !m.hidden).toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: (mi[2] as Color).withOpacity(0.25),
        title: Row(children: [
          Text(mi[0] as String, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gfName, style: const TextStyle(fontSize: 18)),
            Text(busy ? 'typing...' : speaking ? 'speaking...' : listening ? 'listening...' : mi[1] as String,
                style: const TextStyle(fontSize: 12)),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: 'Hands-free call mode',
            icon: Icon(handsFree ? Icons.phone_in_talk : Icons.phone_disabled),
            color: handsFree ? Colors.green : null,
            onPressed: () async {
              await prefs.setBool('handsFree', !handsFree);
              setState(() {});
              if (handsFree) {
                startListening();
              } else {
                stt.stop();
                setState(() => listening = false);
              }
            },
          ),
          IconButton(icon: const Icon(Icons.settings), onPressed: openSettings),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(12),
            itemCount: visible.length,
            itemBuilder: (_, i) {
              final m = visible[i];
              final me = m.role == 'user';
              return Align(
                alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                child: GestureDetector(
                  onTap: me ? null : () => speak(m.text),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: me ? Colors.pink.shade100 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(m.text, style: const TextStyle(fontSize: 16, color: Colors.black87)),
                  ),
                ),
              );
            },
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    hintText: 'Message...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onSubmitted: (t) {
                    if (t.trim().isEmpty) return;
                    ctrl.clear();
                    ask(t.trim());
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () {
                  final t = ctrl.text.trim();
                  if (t.isEmpty) return;
                  ctrl.clear();
                  ask(t);
                },
              ),
              FloatingActionButton(
                mini: true,
                backgroundColor: listening ? Colors.red : Colors.pink,
                onPressed: () async {
                  if (listening) {
                    await stt.stop();
                    setState(() => listening = false);
                  } else {
                    await tts.stop();
                    setState(() => speaking = false);
                    startListening();
                  }
                },
                child: Icon(listening ? Icons.stop : Icons.mic, color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final SharedPreferences prefs;
  const SettingsPage({super.key, required this.prefs});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final key = TextEditingController(text: widget.prefs.getString('apiKey') ?? '');
  late final gf = TextEditingController(text: widget.prefs.getString('gfName') ?? 'Anu');
  late final me = TextEditingController(text: widget.prefs.getString('userName') ?? '');
  late String lang = widget.prefs.getString('lang') ?? 'Manglish';
  late final model = TextEditingController(text: () {
    final m = widget.prefs.getString('model') ?? '';
    return (m.isEmpty || m.startsWith('gemini-2')) ? 'gemini-3.5-flash-lite' : m;
  }());
  late bool voice = widget.prefs.getBool('voiceOn') ?? true;

  void save() {
    final p = widget.prefs;
    p.setString('apiKey', key.text.trim());
    p.setString('gfName', gf.text.trim().isEmpty ? 'Anu' : gf.text.trim());
    p.setString('userName', me.text.trim());
    p.setString('lang', lang);
    p.setString('model', model.text.trim().isEmpty ? 'gemini-3.5-flash-lite' : model.text.trim());
    p.setBool('voiceOn', voice);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        onPopInvokedWithResult: (_, __) => save(),
        child: Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              controller: key,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Gemini API key', helperText: 'aistudio.google.com/apikey', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            TextField(
                controller: gf,
                decoration: const InputDecoration(labelText: 'Girlfriend name', border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(
                controller: me,
                decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder())),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: lang,
              decoration: const InputDecoration(labelText: 'Language', border: OutlineInputBorder()),
              items: ['Manglish', 'Malayalam', 'English']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => lang = v!),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: model,
              decoration: const InputDecoration(
                  labelText: 'Gemini model',
                  helperText: 'Error vannal AI Studio-il ulla puthiya model peru ivide ezhuthu',
                  border: OutlineInputBorder()),
            ),
            SwitchListTile(
                title: const Text('Voice reply (speak aloud)'),
                value: voice,
                onChanged: (v) => setState(() => voice = v)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                await widget.prefs.remove('history');
                await widget.prefs.remove('mood');
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Chat cleared. App restart cheyyu.')));
                }
              },
              child: const Text('Clear chat history'),
            ),
          ]),
        ),
      );
}
