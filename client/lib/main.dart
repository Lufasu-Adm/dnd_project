import 'package:flutter/material.dart';
import 'dart:math'; 
// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

late IO.Socket socket;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initSocketConnection();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: LobbyScreen(),
  ));
}

// 🔌 KONEKSI SOCKET
void initSocketConnection() {
  // GANTI IP: 'http://10.0.2.2:3000' (Emulator) atau IP Laptop (Device Fisik)
  socket = IO.io('http://10.0.2.2:3000', IO.OptionBuilder()
      .setTransports(['websocket'])
      .disableAutoConnect()
      .build());
}

// ==========================================
// 1. LOBBY SCREEN (Create & Join)
// ==========================================
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _roomCodeCtrl = TextEditingController();
  final _createCodeCtrl = TextEditingController();
  double _maxPlayers = 4.0; 

  @override
  void initState() {
    super.initState();
    socket.on('room-error', (msg) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString()), backgroundColor: Colors.red));
    });
    socket.on('room-created', (roomCode) {
      if(mounted) socket.emit('join-room', roomCode);
    });
    socket.on('join-success', (roomCode) {
      if(mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => CharacterCreationScreen(roomCode: roomCode.toString())));
    });
  }

  void _createRoom() {
    if (_createCodeCtrl.text.isEmpty) return;
    if (!socket.connected) socket.connect();
    socket.emit('create-room', {'roomCode': _createCodeCtrl.text.trim(), 'maxPlayers': _maxPlayers.toInt()});
  }

  void _joinRoom() {
    if (_roomCodeCtrl.text.isEmpty) return;
    if (!socket.connected) socket.connect();
    socket.emit('join-room', _roomCodeCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: Text("D&D MULTIPLAYER", style: GoogleFonts.cinzel(fontWeight: FontWeight.bold, color: Colors.amber)),
          backgroundColor: Colors.grey[900],
          bottom: const TabBar(indicatorColor: Colors.amber, labelColor: Colors.amber, unselectedLabelColor: Colors.grey, tabs: [Tab(text: "GABUNG ROOM"), Tab(text: "BUAT ROOM")]),
        ),
        body: TabBarView(
          children: [
            // TAB JOIN
            Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.login, size: 80, color: Colors.blueAccent), const SizedBox(height: 20),
              TextField(controller: _roomCodeCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDecor("Masukkan Kode Room")),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _joinRoom, style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)), child: const Text("GABUNG SEKARANG", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
            ]))),
            // TAB CREATE
            Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_circle_outline, size: 80, color: Colors.amber), const SizedBox(height: 20),
              TextField(controller: _createCodeCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDecor("Buat Kode Room Unik")),
              const SizedBox(height: 30),
              Text("Max Players: ${_maxPlayers.toInt()}", style: const TextStyle(color: Colors.white)),
              Slider(value: _maxPlayers, min: 1, max: 10, divisions: 8, activeColor: Colors.amber, label: _maxPlayers.toInt().toString(), onChanged: (val) => setState(() => _maxPlayers = val)),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _createRoom, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)), child: const Text("BUAT ROOM", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))
            ]))),
          ],
        ),
      ),
    );
  }
  InputDecoration _inputDecor(String label) => InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.grey[900], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amber), borderRadius: BorderRadius.circular(10)));
}

// ==========================================
// 2. CHARACTER CREATION SCREEN
// ==========================================
class CharacterCreationScreen extends StatefulWidget {
  final String roomCode;
  const CharacterCreationScreen({super.key, required this.roomCode});
  @override
  State<CharacterCreationScreen> createState() => _CharacterCreationScreenState();
}

class _CharacterCreationScreenState extends State<CharacterCreationScreen> {
  final _nameCtrl = TextEditingController();
  String? _selectedRace, _selectedClass, _selectedWeapon, _selectedBackground;
  final Map<String, int?> _selectedStats = {'STR': null, 'DEX': null, 'CON': null, 'INT': null, 'WIS': null, 'CHA': null};
  final List<int> _standardArray = [15, 14, 13, 12, 10, 8];
  List<String> _availableWeapons = [];

  // Data Lists (Singkat saja)
  final List<String> _races = ['Human', 'Elf', 'Dwarf', 'Halfling', 'Dragonborn', 'Gnome', 'Half-Elf', 'Half-Orc', 'Tiefling'];
  final List<String> _classes = ['Barbarian', 'Bard', 'Cleric', 'Druid', 'Fighter', 'Monk', 'Paladin', 'Ranger', 'Rogue', 'Sorcerer', 'Warlock', 'Wizard'];
  final List<String> _backgrounds = ['Acolyte', 'Criminal', 'Entertainer', 'Folk Hero', 'Guild Artisan', 'Hermit', 'Noble', 'Outlander', 'Sage', 'Sailor', 'Soldier', 'Urchin'];

  List<int> _getAvailableScores(String currentStatKey) {
    List<int> usedScores = [];
    _selectedStats.forEach((key, value) { if (key != currentStatKey && value != null) usedScores.add(value); });
    return _standardArray.where((score) => !usedScores.contains(score)).toList();
  }

  void _updateWeaponList() {
    if (_selectedClass == null) return;
    Set<String> weaponSet = {};
    if (['Fighter', 'Barbarian', 'Paladin', 'Ranger'].contains(_selectedClass)) {
      weaponSet.addAll(['Greatsword', 'Greataxe', 'Longsword', 'Battleaxe', 'Warhammer', 'Shortsword', 'Rapier', 'Scimitar', 'Longbow', 'Heavy Crossbow', 'Mace', 'Dagger', 'Spear']);
    } else if (['Cleric', 'Druid', 'Warlock', 'Bard'].contains(_selectedClass)) {
      weaponSet.addAll(['Mace', 'Quarterstaff', 'Spear', 'Dagger', 'Light Crossbow', 'Simple Weapon']);
      if (_selectedClass == 'Druid') weaponSet.addAll(['Scimitar']);
      if (_selectedClass == 'Bard') weaponSet.addAll(['Rapier', 'Longsword', 'Shortsword']);
    } else if (_selectedClass == 'Rogue') {
      weaponSet.addAll(['Rapier', 'Shortsword', 'Shortbow', 'Dagger', 'Hand Crossbow']);
    } else {
      weaponSet.addAll(['Dagger', 'Quarterstaff', 'Dart', 'Sling', 'Light Crossbow']);
    }
    setState(() { _availableWeapons = weaponSet.toList()..sort(); _selectedWeapon = null; });
  }

  void submitCharacter() {
    bool statsComplete = !_selectedStats.containsValue(null);
    if (_nameCtrl.text.isEmpty || _selectedRace == null || _selectedClass == null || _selectedWeapon == null || _selectedBackground == null || !statsComplete) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mohon lengkapi data!"), backgroundColor: Colors.redAccent));
      return;
    }
    socket.emit('submit-character', {
      'room': widget.roomCode, 'name': _nameCtrl.text, 'race': _selectedRace, 'cls': _selectedClass, 'weapon': _selectedWeapon, 'background': _selectedBackground, 'stats': _selectedStats,
    });
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(roomCode: widget.roomCode, charName: _nameCtrl.text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text("Buat Karakter"), backgroundColor: Colors.grey[900], foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _nameCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDecor("Nama Karakter")),
            const SizedBox(height: 15),
            DropdownButtonFormField(value: _selectedRace, hint: _hint("Pilih Ras"), items: _mapItems(_races), onChanged: (v) { setState(() => _selectedRace = v); _updateWeaponList(); }, decoration: _inputDecor("Ras"), dropdownColor: Colors.grey[800], style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 15),
            DropdownButtonFormField(value: _selectedClass, hint: _hint("Pilih Kelas"), items: _mapItems(_classes), onChanged: (v) { setState(() => _selectedClass = v); _updateWeaponList(); }, decoration: _inputDecor("Kelas"), dropdownColor: Colors.grey[800], style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 15),
            DropdownButtonFormField(value: _selectedWeapon, hint: _hint("Pilih Senjata"), items: _mapItems(_availableWeapons), onChanged: (v) => setState(() => _selectedWeapon = v), decoration: _inputDecor("Senjata"), dropdownColor: Colors.grey[800], style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 15),
            DropdownButtonFormField(value: _selectedBackground, hint: _hint("Pilih Background"), items: _mapItems(_backgrounds), onChanged: (v) => setState(() => _selectedBackground = v), decoration: _inputDecor("Background"), dropdownColor: Colors.grey[800], style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 30),
            GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 2.5, crossAxisSpacing: 10, mainAxisSpacing: 10,
              children: _selectedStats.keys.map((statKey) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(statKey, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                    DropdownButton<int>(
                      value: _selectedStats[statKey], hint: const Text("-", style: TextStyle(color: Colors.grey)), dropdownColor: Colors.grey[800], underline: Container(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      items: _getAvailableScores(statKey).map((score) => DropdownMenuItem(value: score, child: Text(score.toString()))).toList(),
                      onChanged: (val) => setState(() => _selectedStats[statKey] = val),
                    )
                  ]),
                );
              }).toList(),
            ),
            const SizedBox(height: 40),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: submitCharacter, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber), child: const Text("LANJUT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))),
          ],
        ),
      ),
    );
  }
  InputDecoration _inputDecor(String label) => InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.grey[900], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)));
  List<DropdownMenuItem<String>> _mapItems(List<String> list) => list.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList();
  Widget _hint(String text) => Text(text, style: const TextStyle(color: Colors.grey));
}

// ==========================================
// 3. CHAT SCREEN (WITH WAITING ROOM)
// ==========================================
class ChatScreen extends StatefulWidget {
  final String roomCode;
  final String charName;
  const ChatScreen({super.key, required this.roomCode, required this.charName});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final List<String> _messages = [];
  final _scrollController = ScrollController();
  
  // Status Logic
  bool _isGameStarted = false; 
  bool _amIReady = false; 
  int _currentPlayers = 1;
  int _maxPlayers = 4;
  int _readyPlayers = 0;
  bool _isRolling = false;
  String _rollStat = "";

  @override
  void initState() {
    super.initState();
    _setupSocketListener();
  }

  void _setupSocketListener() {
    socket.off('chat-reply');
    socket.off('lobby-update');
    socket.off('game-started');

    // Update Status Lobby
    socket.on('lobby-update', (data) {
      if(mounted) setState(() { _currentPlayers = data['current']; _maxPlayers = data['max']; _readyPlayers = data['ready']; });
    });

    // Game Start Trigger
    socket.on('game-started', (_) {
      if(mounted) setState(() => _isGameStarted = true);
    });

    // Chat Logic
    socket.on('chat-reply', (data) {
      if(mounted) {
        String message = data.toString();
        setState(() {
          _messages.add(message);
          RegExp rollRegex = RegExp(r'\[ROLL_REQ:\s*([A-Z]+)\]'); 
          Match? match = rollRegex.firstMatch(message);
          if (match != null) {
            _isRolling = true;
            _rollStat = match.group(1) ?? "D20";
          }
        });
        _scrollToBottom();
      }
    });
  }

  void _setReady() {
    setState(() => _amIReady = true);
    socket.emit('player-ready', widget.roomCode);
  }

  void sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    String text = _controller.text.trim();
    socket.emit('chat-message', text);
    setState(() { _messages.add("**Kamu:** $text"); });
    _controller.clear();
    _scrollToBottom();
  }

  void rollDice() {
    int rollResult = Random().nextInt(20) + 1;
    String resultMessage = "(Melempar Dadu $_rollStat)... **Hasil: $rollResult**";
    socket.emit('chat-message', resultMessage);
    setState(() { _messages.add("**Kamu:** $resultMessage"); _isRolling = false; });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    socket.off('chat-reply'); socket.off('lobby-update'); socket.off('game-started');
    _controller.dispose(); _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Room: ${widget.roomCode}", style: const TextStyle(fontSize: 14)), Text(widget.charName, style: const TextStyle(fontSize: 18, color: Colors.amber))]),
        backgroundColor: const Color(0xFF1E1E1E), foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // 1. LAYER CHAT (Selalu ada di belakang)
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController, padding: const EdgeInsets.all(15), itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
                      child: MarkdownBody(data: _messages[index], styleSheet: MarkdownStyleSheet(p: GoogleFonts.poppins(color: Colors.white), strong: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold), listBullet: const TextStyle(color: Colors.amber))),
                    );
                  },
                ),
              ),
              Container(padding: const EdgeInsets.all(10), color: const Color(0xFF1E1E1E), child: _isRolling ? _buildDiceButton() : _buildChatInput()),
            ],
          ),

          // 2. LAYER WAITING ROOM (Overlay jika game belum mulai)
          if (!_isGameStarted)
            Container(
              color: Colors.black.withOpacity(0.95),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.groups, size: 80, color: Colors.amber),
                    const SizedBox(height: 20),
                    Text("MENUNGGU PEMAIN...", style: GoogleFonts.cinzel(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text("Pemain: $_currentPlayers / $_maxPlayers", style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    Text("Siap: $_readyPlayers / $_maxPlayers", style: const TextStyle(color: Colors.greenAccent, fontSize: 16)),
                    const SizedBox(height: 40),
                    
                    _amIReady 
                    ? const Column(children: [CircularProgressIndicator(color: Colors.amber), SizedBox(height: 15), Text("Menunggu teman...", style: TextStyle(color: Colors.white54))])
                    : ElevatedButton(
                        onPressed: _setReady,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                        child: Text("SAYA SIAP (READY)", style: GoogleFonts.cinzel(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      )
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildDiceButton() {
    return SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(onPressed: rollDice, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), icon: const Icon(Icons.casino, color: Colors.black, size: 30), label: Text("ROLL $_rollStat (D20)", style: GoogleFonts.cinzel(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold))));
  }

  Widget _buildChatInput() {
    return Row(children: [
      Expanded(child: TextField(controller: _controller, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: "Tindakanmu...", hintStyle: TextStyle(color: Colors.grey[500]), filled: true, fillColor: Colors.black, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)), onSubmitted: (_) => sendMessage())),
      const SizedBox(width: 10),
      FloatingActionButton(onPressed: sendMessage, backgroundColor: Colors.blueAccent, mini: true, child: const Icon(Icons.send, color: Colors.white))
    ]);
  }
}