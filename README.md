# FNF Multiplayer Prototype
This is a prototype for the Furret Engine multiplayer mode. Contributions are always welcome

## Server to do list
- Make a proper log-in phase (This includes adding states)
- Make the server KNOW what does it have to do WHEN and WHY
- Handle the game properly. Let the player know which song is playing, how many misses and scores does the other players have, etc
- Deal with missing packets
- Adding a proper so-called "DOWNLOAD MODE" phase in which, one user has to send raw bytes to the server. The server has to let know the other players that thereis a download going on. The players will have to stop parsing incoming JSONs, and listen for the RAW BYTES that the player is going to send

## Client to do list
- Almost everything, I wanna finish the server first, I will focus on the client later