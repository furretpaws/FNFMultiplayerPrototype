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
						@:privateAccess
						sessions.remove(sessions[i]);
					}
				}
				trace(disconnectedBro);
				for (i in 0...sessions.length) {
					var uhoh:Bytes = Bytes.ofString(haxe.Json.stringify({
						event: "PLAYER_DISCONNECTED",
						d: {
							username: disconnectedBro
						}
					}));
					@:privateAccess
					sessions[i].socket.output.writeFullBytes(uhoh, 0, uhoh.length);
				}
			} catch (err) {
				trace("what the fuck");
			}
		}
		server.onData = (bytes:IncomingBytes) -> {
			// QUICK CHECK, as there are some people that are stupid enough to try and put this on their browser
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
								for (i in 0...sessions.length) {
									var socketFound = false;
									@:privateAccess
									if (bytes.socket == sessions[i].socket) {
										socketFound = true;
									}
									if (socketFound) {
										bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
											error: true,
											d: "You cannot longer use these payloads, these are only for non-logged in users"
										})));
									} else {
										bytes.send(haxe.io.Bytes.ofString(haxe.Json.stringify({
											error: false,
											d: {
												serverVersion: "1.5.2h",
												hostedOn: "Microsoft Windows 11 Pro",
												players: sessions.length
											}
										})));
										bytes.socket.close();
									}
								}
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
											var session:Session = new Session(bytes.socket.peer().host.host, bytes.socket.peer().port, username, version, os,
												bytes.socket);
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
												error: false,
												d: {
													status: "CONNECTED",
													players: {
														total: sessions.length,
														users: users
													},
													game_status: "NOT_IN_GAME",
													voting_for_song: "Dying-Slowly"
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
										d: "The event you have requested is for logged in users only. As a result, you will be disconnected from the server."
									})));
									bytes.socket.close();
								}
						}
					}
				}
			}
		}
		server.start();
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

	public function new(ip:String, port:Int, username:String, furretEngineVersion:String, platform:String, socket:Socket) {
		this.ip = ip;
		this.port = port;
		this.username = username;
		this.furretEngineVersion = furretEngineVersion;
		this.socket = socket;
	}
}
