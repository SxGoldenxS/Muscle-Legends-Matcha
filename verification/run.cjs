const fs = require('node:fs');
const path = require('node:path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

async function main() {
  const port = fs.readFileSync(path.join(__dirname, '..', 'matcha.lua'), 'utf8');
  const url = port.match(/https:\/\/gitlab\.com\/ellijahheath\/rem-ui\/-\/raw\/[a-f0-9]{40}\/rem_v6-matcha\.lua/)[0];
  let rem;
  if (process.argv[2]) rem = fs.readFileSync(process.argv[2], 'utf8');
  else {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`REM download failed: HTTP ${response.status}`);
    rem = await response.text();
  }
  const state = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(state);
  for (const [name, value] of [['PORT_SOURCE', port], ['REM_SOURCE', rem], ['REM_PATCHED_SOURCE', rem]]) {
    lua.lua_pushstring(state, to_luastring(value));
    lua.lua_setglobal(state, to_luastring(name));
  }
  if (lauxlib.luaL_loadbuffer(state, to_luastring(rem), null, to_luastring('@rem_v6.lua')) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  }
  lua.lua_pop(state, 1);
  const contract = fs.readFileSync(path.join(__dirname, 'contract.lua'), 'utf8');
  if (lauxlib.luaL_loadbuffer(state, to_luastring(contract), null, to_luastring('@contract.lua')) !== lua.LUA_OK ||
      lua.lua_pcall(state, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
