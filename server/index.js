require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require("socket.io");
const Groq = require("groq-sdk");

// --- VALIDATION ---
if (!process.env.GROQ_API_KEY) {
    console.error("❌ ERROR: Missing GROQ_API_KEY in .env file.");
    process.exit(1);
}

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

const groq = new Groq({ apiKey: process.env.GROQ_API_KEY });

const MAX_CONTEXT_HISTORY = 15; 

// --- ULTIMATE SYSTEM PROMPT ---
const SYSTEM_PROMPT = `
ROLE: Anda adalah AI Game Engine untuk Text-Based RPG D&D 5e (Bahasa Indonesia).
STATUS: Anda bukan hanya narator, Anda adalah wasit logika yang ketat.

=== PROTOKOL UTAMA: STATE MACHINE (WAJIB PATUH) ===
Anda memiliki dua MODE. Anda hanya boleh berada di satu mode dalam satu waktu.

[MODE 1: FASE INPUT USER]
- AKTIF SAAT: Memulai cerita, mendeskripsikan tempat, atau memberikan pilihan.
- OUTPUT: Deskripsi situasi + Daftar Pilihan (1., 2., 3.) atau Pertanyaan "Apa yang kamu lakukan?".
- LARANGAN KERAS: JANGAN PERNAH MENULIS TAG [ROLL_REQ] DI MODE INI.

[MODE 2: FASE RESOLUSI DADU]
- AKTIF SAAT: HANYA SETELAH User mengirim pesan tindakan spesifik (misal: "Aku serang", "Aku panjat").
- OUTPUT: Narasi singkat reaksi lingkungan + Tag [ROLL_REQ: STAT].
- ATURAN STOP: Setelah menulis tag [ROLL_REQ:...], BERHENTI MENULIS TOTAL.

=== MEKANISME DADU ===
- Tag: **[ROLL_REQ: KODE]** (Valid: STR, DEX, CON, INT, WIS, CHA).
- Jangan pernah memprediksi hasil angka dadu.
`;

// --- MEMORY ---
let roomData = {}; 
let players = {};

function buildMessageHistory(roomCode) {
    const data = roomData[roomCode];
    if (!data) return [];
    return [ data.system, ...data.characters, ...data.chat ];
}

io.on('connection', (socket) => {
    console.log(`🔌 Player Connected: ${socket.id}`);

    // 1. CREATE ROOM
    socket.on('create-room', ({ roomCode, maxPlayers }) => {
        if (!roomCode) return;
        if (roomData[roomCode]) {
            socket.emit('room-error', "Room sudah ada! Gunakan kode lain.");
            return;
        }
        roomData[roomCode] = {
            system: { role: "system", content: SYSTEM_PROMPT },
            config: { maxPlayers: parseInt(maxPlayers) || 4 }, 
            characters: [], 
            chat: [],
            connectedPlayers: [], 
            readyPlayers: []      // List pemain yang sudah klik READY
        };
        console.log(`✨ Room Created: ${roomCode} | Max: ${maxPlayers}`);
        socket.emit('room-created', roomCode); 
    });

    // 2. JOIN ROOM
    socket.on('join-room', (roomCode) => {
        if (!roomCode) return;
        // Auto-create default room jika join manual
        if (!roomData[roomCode]) {
            roomData[roomCode] = {
                system: { role: "system", content: SYSTEM_PROMPT },
                config: { maxPlayers: 4 }, 
                characters: [], chat: [], connectedPlayers: [], readyPlayers: []
            };
        }

        const room = roomData[roomCode];
        if (room.connectedPlayers.length >= room.config.maxPlayers) {
            socket.emit('room-error', "Room Penuh!");
            return;
        }

        socket.join(roomCode);
        if (!room.connectedPlayers.includes(socket.id)) {
            room.connectedPlayers.push(socket.id);
        }
        
        socket.emit('join-success', roomCode);
        
        // Broadcast info lobby terbaru
        io.to(roomCode).emit('lobby-update', {
            current: room.connectedPlayers.length,
            max: room.config.maxPlayers,
            ready: room.readyPlayers.length
        });
    });

    // 3. SUBMIT CHARACTER
    socket.on('submit-character', (charData) => {
        players[socket.id] = charData;
        const roomCode = charData.room;
        if (roomData[roomCode]) {
            roomData[roomCode].characters.push({
                role: "user",
                content: `[PLAYER INFO] Name: ${charData.name}, Class: ${charData.cls}, Race: ${charData.race}.`
            });
        }
    });

    // 4. PLAYER READY (WAITING ROOM LOGIC)
    socket.on('player-ready', async (roomCode) => {
        const room = roomData[roomCode];
        if (!room) return;

        if (!room.readyPlayers.includes(socket.id)) {
            room.readyPlayers.push(socket.id);
        }

        // Update status lobby ke semua orang
        io.to(roomCode).emit('lobby-update', {
            current: room.connectedPlayers.length,
            max: room.config.maxPlayers,
            ready: room.readyPlayers.length
        });

        // CEK START GAME
        if (room.readyPlayers.length >= room.config.maxPlayers) {
            console.log(`🚀 All players ready in ${roomCode}. Starting Game!`);
            
            // 1. Beritahu Frontend game mulai
            io.to(roomCode).emit('game-started');

            // 2. Trigger Intro AI otomatis
            const introMsg = "Semua pemain telah berkumpul. Perkenalkan dunia, suasana sekitar, dan tanyakan apa yang mereka lakukan.";
            room.chat.push({ role: "system", content: introMsg }); 

            try {
                const fullContext = buildMessageHistory(roomCode);
                const completion = await groq.chat.completions.create({
                    messages: fullContext,
                    model: "llama-3.3-70b-versatile",
                    temperature: 0.7,
                });
                const aiResponse = completion.choices[0]?.message?.content || "Welcome adventurers...";
                
                room.chat.push({ role: "assistant", content: aiResponse });
                io.to(roomCode).emit('chat-reply', aiResponse);

            } catch (e) { console.error(e); }
        }
    });

    // 5. CHAT MESSAGE
    socket.on('chat-message', async (msg) => {
        const player = players[socket.id];
        if (!player || !roomData[player.room]) return;
        const roomCode = player.room;
        
        const identityMsg = `[${player.name}]: ${msg}`;
        roomData[roomCode].chat.push({ role: "user", content: identityMsg });

        if (roomData[roomCode].chat.length > MAX_CONTEXT_HISTORY) {
            roomData[roomCode].chat = roomData[roomCode].chat.slice(-MAX_CONTEXT_HISTORY);
        }

        try {
            const fullContext = buildMessageHistory(roomCode);
            const completion = await groq.chat.completions.create({
                messages: fullContext,
                model: "llama-3.3-70b-versatile",
                temperature: 0.6, 
            });
            let aiResponse = completion.choices[0]?.message?.content || "...";
            
            // --- SAFETY NET (HALLUCINATION STOPPER) ---
            const hasOptions = /\b\d+\.\s/.test(aiResponse) || aiResponse.includes("Apa yang kamu lakukan?");
            const rollTagMatch = aiResponse.match(/\[ROLL_REQ:\s*([A-Z]+)\]/i);

            if (hasOptions && rollTagMatch) {
                // Hapus roll jika ada opsi
                aiResponse = aiResponse.replace(/\[ROLL_REQ:\s*[A-Z]+\]/gi, "");
            } else if (rollTagMatch) {
                // Potong teks setelah roll request
                const cutOffIndex = rollTagMatch.index + rollTagMatch[0].length;
                aiResponse = aiResponse.substring(0, cutOffIndex);
            }
            // ------------------------------------------

            roomData[roomCode].chat.push({ role: "assistant", content: aiResponse });
            io.to(roomCode).emit('chat-reply', aiResponse);
        } catch (error) { console.error(error); }
    });

    socket.on('disconnect', () => {
        for (const [code, room] of Object.entries(roomData)) {
            const idx = room.connectedPlayers.indexOf(socket.id);
            if (idx !== -1) room.connectedPlayers.splice(idx, 1);
            
            const readyIdx = room.readyPlayers.indexOf(socket.id);
            if (readyIdx !== -1) room.readyPlayers.splice(readyIdx, 1);

            io.to(code).emit('lobby-update', {
                current: room.connectedPlayers.length,
                max: room.config.maxPlayers,
                ready: room.readyPlayers.length
            });
        }
        delete players[socket.id];
    });
});

server.listen(3000, () => { console.log('⚔️ Server running on 3000'); });