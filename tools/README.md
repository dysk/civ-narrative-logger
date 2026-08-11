# Enabling logging on a machine

Logging is off by default everywhere. To enable it on a machine (the
pitboss server, or your own machine for single-player testing), copy
`civ-narrative-logger-1.db` from this folder into the game's
`ModUserData` folder:

| Platform | ModUserData location |
|---|---|
| Windows | `Documents\My Games\Sid Meier's Civilization 5\ModUserData\` |
| macOS | `~/Documents/Aspyr/Sid Meier's Civilization 5/ModUserData/` |
| Linux (wine pitboss) | `~/.wine/drive_c/users/<user>/Documents/My Games/Sid Meier's Civilization 5/ModUserData/` |

To disable logging, delete the file (or set the flag to 0 with
sqlite3, where available):

```sh
sqlite3 civ-narrative-logger-1.db \
  "UPDATE SimpleValues SET Value = 0 WHERE Name = 'enabled';"
```

The file is a plain SQLite database with a single `SimpleValues` row
(`enabled` = `1`) - exactly what the addon reads through
`Modding.OpenUserData("civ-narrative-logger", 1)`. To regenerate it:

```sh
sqlite3 civ-narrative-logger-1.db \
  "CREATE TABLE IF NOT EXISTS SimpleValues (Name TEXT PRIMARY KEY, Value);
   INSERT OR REPLACE INTO SimpleValues (Name, Value) VALUES ('enabled', 1);"
```
