// SERVER - FURRET ENGINE MULTIPLAYER PROTOTYPE
/**
	TODO:
	- Make a proper log-in phase (This includes adding states)
	- Make the server KNOW what does it have to do WHEN and WHY
	- Handle the game properly. Let the player know which song is playing, how many misses and scores does the other players have, etc
	- Deal with missing packets
	- Adding a proper so-called "DOWNLOAD MODE" phase in which, one user has to send raw bytes to the server. The server has to let know the other players that there is a download going on. The players will have to stop parsing incoming JSONs, and listen for the RAW BYTES that the player is going to send
**/
// Here we go... I started coding at 12/07/2023 - 22:09
import haxe.io.Bytes;
import socket.Server;
import sys.net.Socket;
import socket.Server.IncomingBytes;

using StringTools;

class Main {
	static var server:Server;
	static var sessions:Array<Session> = [];
	static var downloadingshit:Bool = false;
	static var socketSendingFile:Socket = null;
	static var inGame:Bool = false;
	static var currentSong:String = "No song";
	static var ownershipKey:String = "i love furries";

	static function main() {
		server = new Server("127.0.0.1", 8080);
		server.onStarted = () -> {
			trace("FNF: Server started at 127.0.0.1:8080");
		}
		server.onClientConnect = (socket:Socket) -> {
			trace("Someone tried to connect, they are " + socket.peer().host);
		}
		server.onClientDisconnect = (socket:Socket) -> {
			try {
				trace("someone disconnected i think");
				var disconnectedBro:String = "";
				for (i in 0...sessions.length) {
					@:privateAccess
					if (sessions[i].socket == socket) {
						@:privateAccess
						disconnectedBro = sessions[i].username;
						for (i in 0...sessions.length) {
							if (sessions[i].socket != socket) {
								var uhoh:Bytes = Bytes.ofString(haxe.Json.stringify({
									event: "PLAYER_DISCONNECTED",
									d: {
										username: disconnectedBro
									}
								}));
								@:privateAccess
								sessions[i].socket.output.writeFullBytes(uhoh, 0, uhoh.length);
							}
						}
						@:privateAccess
						sessions.remove(sessions[i]);
					}
				}
			} catch (err) {
				/*trace("what the fuck");
					trace(err); */
			}
		}
		server.onData = (bytes:IncomingBytes) -> {
			// QUICK CHECK, as there are some people that are stupid enough to try and put this on their browser
			trace(bytes.bytes.toString());
			if (bytes.bytes.toString().split("\n")[0].contains("GET") && bytes.bytes.toString().split("\n")[0].contains("HTTP/1.")) {
				trace("blud is trying to access this as a webpage, fuck them lol");
				var responselol:String = "<html><head><title>What are you doing???</title></head><body><h1>HTTP/1.1 400 Bad Request</h1><p>What are you doing? This is a Furret Engine (Friday Night Funkin') server ONLY. Access it from the original FNF engine. <br>This is not a webpage, what are you thinking?<br><br>Download the engine at: <a href=\"https://github.com/FurretDev/Furret-Engine\">https://github.com/FurretDev/Furret-Engine</a></p></body></html>";
				var strbuf = new StringBuf();
				strbuf.add("HTTP/1.1 400 Bad Request\r\n");
				strbuf.add("Content-Type: text/html\r\n");
				strbuf.add("Content-Length: " + responselol.length + "\r\n");
				strbuf.add("\r\n" + responselol);
				bytes.send(haxe.io.Bytes.ofString(strbuf.toString()));
				bytes.socket.close();
			} else {
				if (downloadingshit) {
					if (!isBroLoggedIn(bytes.socket)) {
						bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
							error: true,
							d: "Log in temporarily disabled on downloading mode"
						})));
					} else {
						if (bytes.socket == socketSendingFile) {
							broadcastMessageExceptForUser(bytes.socket, bytes.bytes);
							downloadingshit = false;
							socketSendingFile = null;
						}
					}
				} else {
					var json:Dynamic = null;
					var failed:Bool = false;
					var error:String = "";
					try {
						json = haxe.Json.parse(bytes.bytes.toString());
					} catch (err) {
						failed = true;
						error = err.toString();
					}
					if (failed) {
						try {
							bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
								error: true,
								d: "This is not a valid JSON request? Make sure the JSON you sent is PARSABLE and it's VALID. Error: " + error
							})));
							bytes.socket.close();
						} catch (err) {
							trace("what the fuck?");
						}
					} else {
						if (json.event == null) {
							bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
								error: true,
								d: "Expected a \"event\" parameter in the JSON. Allowed events: \"GET_INFO\", \"CONNECT\""
							})));
							bytes.socket.close();
						} else {
							switch (json.event) {
								/**
									EVENTS FOR NOT LOGGED-IN USERS
								**/
								case "GET_INFO":
									bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
										error: false,
										d: {
											serverVersion: "1.5.2h",
											hostedOn: "Microsoft Windows 11 Pro",
											players: sessions.length,
											onAMatch: false
										}
									})));
									bytes.socket.close();
								case "CONNECT":
									trace("kekw");
									var socketFound = false;
									for (i in 0...sessions.length) {
										@:privateAccess
										if (bytes.socket == sessions[i].socket) {
											socketFound = true;
										}
									}
									if (socketFound) {
										bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
											error: true,
											d: "You cannot longer use these payloads, these are only for non-logged in users"
										})));
									} else {
										var username:String = json.d.username;
										var version:String = json.d.version;
										var os:String = json.d.os;
										if (username == null || version == null || os == null) {
											bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
												error: true,
												d: "There are invalid arguments in your JSON payload or there are missing arguments"
											})));
											bytes.socket.close();
										} else {
											var duplicated:Bool = false;
											for (i in 0...sessions.length) {
												@:privateAccess
												if (username.toLowerCase() == sessions[i].username.toLowerCase()) {
													duplicated = true;
												}
											}
											if (duplicated) {
												bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
													error: true,
													d: "There is already a user by the name of " + username
												})));
												bytes.socket.close();
											} else {
												var session:Session = new Session(bytes.socket.peer().host.host, bytes.socket.peer().port, username, version,
													os, bytes.socket);
												sessions.push(session);
												var users:Array<Dynamic> = [];
												@:privateAccess
												for (i in 0...sessions.length) {
													users.push({
														username: sessions[i].username,
														platform: sessions[i].platform
													});
												}
												bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
													event: "READY",
													error: false,
													d: {
														status: "CONNECTED",
														players: {
															total: sessions.length,
															users: users
														},
														game_status: "NOT_IN_GAME",
														voting_for_song: currentSong
													}
												})));
												for (i in 0...sessions.length) {
													@:privateAccess
													if (sessions[i].socket != bytes.socket) {
														var bytes:Bytes = Bytes.ofString(haxe.Json.stringify({
															event: "PLAYER_CONNECTED",
															d: {
																username: username,
																platform: os,
															}
														}));
														sessions[i].socket.output.writeFullBytes(bytes, 0, bytes.length);
													}
												}
											}
										}
									}
								case "LOBBY_NOTE_PRESSED":
									if (!inGame) {
										var socketFound:Bool = false;
										for (i in 0...sessions.length) {
											@:privateAccess
											if (bytes.socket == sessions[i].socket) {
												socketFound = true;
											}
										}
										if (socketFound) {
											var note_pressed:String = json.d.notepress;
											if (note_pressed != "LEFT" && note_pressed != "DOWN" && note_pressed != "UP" && note_pressed != "RIGHT") {
												bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
													error: true,
													d: "Missing arguments \"notepress\". It has to be either \"LEFT\", \"DOWN\", \"UP\", \"RIGHT\""
												})));
												bytes.socket.close();
											} else {
												var username:String = checkWhoDidThis(bytes.socket);
												trace(username);
												if (username == null) {
													bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
														error: true,
														d: "We are sorry, but you might have a zombified connection. We don't know who are you. Please, try to reconnect",
														disconnect: true
													})));
													bytes.socket.close();
												} else {
													bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
														status: "OK",
														d: {
															event: "LOBBY_NOTE_PRESSED"
														}
													})));
													broadcastMessageExceptForUser(bytes.socket, Bytes.ofString(haxe.Json.stringify({
														event: "LOBBY_NOTE_PRESSED",
														d: {
															username: username,
															notepressed: note_pressed
														}
													})));
												}
											}
										} else {
											bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
												error: true,
												d: "You can't use that event in-game"
											})));
										}
									} else {
										bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
											error: true,
											d: "The event you have requested is for logged in users only. As a result, you will be disconnected from the server."
										})));
										bytes.socket.close();
									}
								case "CHAT":
									trace("kekw");
									if (isBroLoggedIn(bytes.socket)) {
										trace("what");
										var message:String = json.d.message;
										if (message != null) {
											bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
												status: "OK",
												d: {
													event: "CHAT",
													message: message
												}
											})));
											var username:String = checkWhoDidThis(bytes.socket);
											broadcastMessageExceptForUser(bytes.socket, Bytes.ofString(haxe.Json.stringify({
												event: "CHAT",
												d: {
													username: username,
													message: message
												}
											})));
										} else {
											bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
												status: "NOT_OK",
												d: {
													event: "CHAT",
													failed: true,
													error: "Message cannot be NULL"
												}
											})));
										}
									} else {
										trace("kek?");
										bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
											error: true,
											d: "The event you have requested is for logged in users only. As a result, you will be disconnected from the server."
										})));
										bytes.socket.close();
									}
								case "REQ_DOWNLOAD_MODE":
									var filename:String = json.d.filename;
									var type:String = json.d.type;
									var path:String = json.d.path;
									if (isBroLoggedIn(bytes.socket)) {
										if (filename == null) {
											bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
												status: "NOT_OK",
												d: {
													event: "REQ_DOWNLOAD_MODE",
													failed: true,
													error: "Filename cannot be NULL"
												}
											})));
										} else {
											switch (type) {
												case "SONG":
												// code voting mode
												case "OTHER":
													if (path == null) {
														bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
															status: "NOT_OK",
															d: {
																event: "REQ_DOWNLOAD_MODE",
																failed: true,
																error: "PATH cannot be NULL on OTHER type"
															}
														})));
													} else {
														bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
															status: "OK",
															d: {
																status: "SEND_FILE",
																event: "REQ_DOWNLOAD_MODE",
																failed: false
															}
														})));
														broadcastMessageExceptForUser(bytes.socket, Bytes.ofString(haxe.Json.stringify({
															event: "DOWNLOAD_MODE",
															d: {
																human_readable: "All clients have to stop parsing incoming JSON messages and listen for incoming raw bytes.",
																filename: filename
															}
														})));
														downloadingshit = true;
														socketSendingFile = bytes.socket;
													}
											}
										}
									}
								case "TAKE_OWNERSHIP":
									if (isBroLoggedIn(bytes.socket)) {
										var key:String = json.d.key;
										if (key == ownershipKey) {
											for (i in 0...sessions.length) {
												@:privateAccess
												if (sessions[i].socket == bytes.socket) {
													@:privateAccess
													sessions[i].ownership = true;
												}
											}
											bytes.send(Bytes.ofString(haxe.Json.stringify({
												event: "OWNERSHIP_GRANTED",
												d: {
													status: "OK"
												}
											})));
										}
									}
								case "FORCE_SET_SONG":
									var song:String = json.d.song;
									if (isBroLoggedIn(bytes.socket)) {
										if (broHasOwnership(bytes.socket)) {
											if (song == null) {
												bytes.send(Bytes.ofString(haxe.Json.stringify({
													event: "FORCE_SET_SONG",
													d: {
														status: "NOT_OK",
														error: true,
														error_message: "SONG cannot be NULL"
													}
												})));
											} else {
												bytes.send(Bytes.ofString(haxe.Json.stringify({
													event: "FORCE_SET_SONG",
													d: {
														status: "OK",
														song: song
													}
												})));
											}
										} else {
											bytes.send(Bytes.ofString(haxe.Json.stringify({
												event: "FORCE_SET_SONG",
												d: {
													status: "NOT_OK",
													error: true,
													error_message: "This event is only for users who have ownership"
												}
											})));
										}
									} else {
										bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
											error: true,
											d: "The event you have requested is for logged in users only. As a result, you will be disconnected from the server."
										})));
										bytes.socket.close();
									}
								case "KICK_USER":
									var username:String = json.d.username;
									if (isBroLoggedIn(bytes.socket)) {
										if (broHasOwnership(bytes.socket)) {
											if (username == null) {
												bytes.send(Bytes.ofString(haxe.Json.stringify({
													event: "KICK_USER",
													d: {
														status: "NOT_OK",
														error: true,
														error_message: "USERNAME cannot be NULL"
													}
												})));
											} else {
												var kicked:Bool = false;
												for (i in 0...sessions.length) {
													@:privateAccess
													if (sessions[i].username == username) {
														kicked = true;
														sessions[i].socket.output.writeFullBytes(Bytes.ofString(haxe.Json.stringify({
															event: "KICK_USER",
															d: {
																kicked: true,
																disconnect: true,
																what_happened: "You have been kicked from this server"
															}
														})), 0, Bytes.ofString(haxe.Json.stringify({
															event: "KICK_USER",
															d: {
																kicked: true,
																disconnect: true,
																what_happened: "You have been kicked from this server"
															}
														})).length);
														sessions[i].socket.close();
													}
												}
												if (kicked) {
													bytes.send(Bytes.ofString(haxe.Json.stringify({
														event: "KICK_USER",
														d: {
															status: "OK",
															user: username
														}
													})));
												} else {
													bytes.send(Bytes.ofString(haxe.Json.stringify({
														event: "KICK_USER",
														d: {
															status: "NOT_OK",
															error: true,
															error_message: "I couldn't find " + username
														}
													})));
												}
											}
										}
									} else {
										bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
											error: true,
											d: "The event you have requested is for logged in users only. As a result, you will be disconnected from the server."
										})));
										bytes.socket.close();
									}
 							}
						}
					}
				}
			}
		}
		server.start();
	}

	static function isBroLoggedIn(socket:Socket) {
		var socketFound:Bool = false;
		@:privateAccess
		for (i in 0...sessions.length) {
			@:privateAccess
			if (socket == sessions[i].socket) {
				socketFound = true;
			}
		}
		return socketFound;
	}

	static function broHasOwnership(socket:Socket) {
		var socketFound:Bool = false;
		@:privateAccess
		for (i in 0...sessions.length) {
			@:privateAccess
			if (socket == sessions[i].socket) {
				@:privateAccess
				socketFound = sessions[i].ownership;
			}
		}
		return socketFound;
	}

	static function checkWhoDidThis(socket:Socket):String {
		var username:String = null;
		@:privateAccess
		for (i in 0...sessions.length) {
			@:privateAccess
			if (socket == sessions[i].socket) {
				@:privateAccess
				username = sessions[i].username;
			}
		}
		return username;
	}

	static function broadcastMessageExceptForUser(socket:Socket, bytes:Bytes) {
		for (i in 0...sessions.length) {
			@:privateAccess
			if (sessions[i].socket != socket) {
				sessions[i].socket.output.writeFullBytes(bytes, 0, bytes.length);
			}
		}
	}
}

class Session {
	var ip:String;
	var port:Int;
	var username:String;
	var furretEngineVersion:String;
	var platform:String;
	var socket:Socket;
	var ownership:Bool = false;

	public function new(ip:String, port:Int, username:String, furretEngineVersion:String, platform:String, socket:Socket) {
		this.ip = ip;
		this.port = port;
		this.username = username;
		this.furretEngineVersion = furretEngineVersion;
		this.socket = socket;
	}
}
