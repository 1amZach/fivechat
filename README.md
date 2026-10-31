# fivechat

A chat for roleplay servers that replaces the default `chat` resource. Local and OOC channels, `/me` and `/do`, tweets, adverts, 911 calls, staff chat and mutes, in tabs.

Everything written for the default chat keeps working: `chat:addMessage`, suggestions, templates and the `chatMessage` event.

![Preview](docs/preview.png)

## Features

- Plain messages only reach players nearby, 20m by default. Messages from further away show faded. Turn it off and chat is global like the default one.
- `/me` and `/do` for nearby players, also shown over the player's head for a few seconds
- Tabs for All, Local, OOC, Staff and 911, with a dot when something new comes in on a tab you're not looking at. Staff only see the Staff tab, police and EMS the 911 tab.
- Typing in the OOC tab sends OOC, typing in the Staff tab sends staff chat
- 911 calls go to every police and EMS player on duty, with the street name and a blip where the call came from
- Character names on Qbox, QBCore and ESX. You choose which messages use them and which use the FiveM name.
- Your name or `@` and your id in a message highlights it for you
- Staff can mute a player for a number of minutes. Mutes last through restarts.
- Rate limit, repeated message limit and max length checked on the server. Colour codes are stripped from what players type, and nothing they type is ever treated as HTML.
- Suggestions with parameters for every command, Tab to complete, Up and Down for your last messages
- Fades out a few seconds after the last message, like the default chat

Press **T** to open it. Players can change the key in their FiveM settings. Page Up and Page Down scroll.

## Commands

| | |
|---|---|
| `/me <action>` | Something your character does, to people nearby |
| `/do <description>` | What others can see happening, to people nearby |
| `/ooc <message>` | Out of character, to everyone |
| `/looc <message>` | Out of character, to people nearby |
| `/twt <message>` | A tweet under your character name |
| `/ad <message>` | An advert, free unless you set a price |
| `/911 <message>` | Call the police and EMS |
| `/clear` | Clear your own chat |
| `/sc <message>` | Staff chat, only without fivecord |
| `/mute <id> <minutes> [reason]` | Staff. Stop a player from talking in chat. 911 still works |
| `/unmute <id>` | Staff |

## With the others

- **[fivecord](https://github.com/1amZach/fivecord):** its staff roles decide who is staff. Its own `/sc` staff chat is used instead of fivechat's, so it still reaches Discord, and its messages land in the Staff tab. Mutes are posted to its `staff` log channel.
- **[fivelog](https://github.com/1amZach/fivelog):** plain messages are logged through `chatMessage` as before. `/me`, `/do`, `/ooc`, `/twt`, `/ad` and `/911` are logged too.
- **[fivepanel](https://github.com/1amZach/fivepanel):** mutes and unmutes show in the activity feed.

## Install

1. Remove the default `chat` resource from your `server.cfg`, or delete it from your resources. fivechat takes its place, so anything that depends on `chat` still starts.

2. Drop `fivechat` into your resources and add to `server.cfg` after your framework and fivecord:

   ```
   ensure fivechat
   ```

3. Without fivecord, mark staff with an ace:

   ```
   add_ace group.admin fivechat.staff allow
   ```

Local chat needs OneSync, which is on by default.

## Config

`config.lua`:

| | |
|---|---|
| `Config.key` | Default key to open the chat |
| `Config.localChat` | Plain messages only to people nearby, or to everyone |
| `Config.range` | How far `say`, `me`, `do` and `looc` carry |
| `Config.commands` | Command names, `false` turns one off |
| `Config.names` | `'character'` or `'player'` for each kind of message |
| `Config.showIds` | Server ids next to names |
| `Config.overhead` | `/me` and `/do` over heads, for how long and how far |
| `Config.ads` | Price of an advert and the account it comes from. 0 is free |
| `Config.calls` | Jobs that get 911 calls, on duty only, blip look and how long it stays |
| `Config.staffAce` | Ace for staff without fivecord |
| `Config.maxLength` | Longest message |
| `Config.spam` | Messages allowed per few seconds, and how often the same one can be repeated |
| `Config.fadeAfter` | Seconds before the closed chat fades |

## For other resources

The default chat's events all work as before:

```lua
-- client
TriggerEvent('chat:addMessage', { color = { 255, 92, 108 }, args = { 'Dispatch', 'Unit 4 responding' } })
TriggerEvent('chat:addSuggestion', '/car', 'Spawn a car', { { name = 'model', help = 'adder' } })
TriggerEvent('chat:addTemplate', 'well', '<b>{0}</b> {1}')
TriggerEvent('chat:clear')

-- server
TriggerClientEvent('chat:addMessage', source, { args = { '^1Server', 'Restart in 5 minutes' } })
exports.fivechat:addMessage(-1, { args = { 'Server', 'hello' } })

AddEventHandler('chatMessage', function(src, name, message)
    if message:find('badword') then CancelEvent() end
end)
```

Add `channel = 'ooc'`, `'local'`, `'staff'` or `'call'` to a message to put it in that tab. Templates can use simple markup like `<b>`, `<i>` and `<span style>`. Scripts, images, links and event attributes are removed, and arguments are always inserted as text.

```lua
if exports.fivechat:isMuted(source) then return end
exports.fivechat:mute(source, 10, 'Spamming')
exports.fivechat:unmute(source)
```

## Testing

```
lua5.4 test/run.lua
```

Runs the server side against a fake FiveM server.

## Support

Made by **IamZach**. Questions, bugs or ideas: [discord.gg/agn](https://discord.gg/agn)

## License

MIT
