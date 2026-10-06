// edits that land while the first analysis is still running used to abort the server (salsa cancels by unwinding)
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';

const [wasmtime, wasm, dir] = process.argv.slice(2);
const text = (n) => `use std::collections::HashMap;\nfn main() {\n    let mut m: HashMap<String, i32> = HashMap::new();\n    m.insert("a".to_string(), ${n});\n    let x: i32 = "oops";\n}\n`;
const p = spawn(wasmtime, ['run', '-W', 'threads=y', '-S', 'threads=y', '--dir', `${dir}::/`, wasm], { stdio: ['pipe', 'pipe', 'inherit'] });
const send = (o) => { const s = JSON.stringify(o); p.stdin.write(`Content-Length: ${Buffer.byteLength(s)}\r\n\r\n${s}`); };
const pending = new Map();
let nextId = 2;
const request = (method, params) => new Promise((resolve, reject) => {
	const id = nextId++;
	const timer = setTimeout(() => {
		pending.delete(id);
		reject(new Error('LSP request timed out: ' + method));
	}, 30000);
	pending.set(id, (msg) => {
		clearTimeout(timer);
		if (msg.error) reject(new Error(msg.error.message));
		else resolve(msg.result);
	});
	send({jsonrpc: '2.0', id, method, params});
});
let buf = Buffer.alloc(0);
let sawError = false;
let exitCode;
process.on('exit', () => p.kill());
p.on('exit', (c) => {
	exitCode = c;
	for (const reply of pending.values()) reply({error: {message: `server exited with code ${c}`}});
	pending.clear();
});
p.stdout.on('data', (d) => {
	buf = Buffer.concat([buf, d]);
	for (;;) {
		const h = buf.indexOf('\r\n\r\n');
		if (h < 0) return;
		const len = Number(/Content-Length: (\d+)/.exec(buf.slice(0, h).toString())[1]);
		if (buf.length < h + 4 + len) return;
		const msg = JSON.parse(buf.slice(h + 4, h + 4 + len).toString());
		buf = buf.slice(h + 4 + len);
		if (msg.method === 'textDocument/publishDiagnostics' && msg.params.diagnostics.some((x) => x.code === 'E0308')) sawError = true;
		if (msg.id !== undefined && msg.method) send({ jsonrpc: '2.0', id: msg.id, result: null });
		if (msg.id !== undefined && !msg.method) {
			pending.get(msg.id)?.(msg);
			pending.delete(msg.id);
		}
	}
});
send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { processId: null, rootUri: 'file:///ws', capabilities: {}, initializationOptions: { linkedProjects: ['/ws/rust-project.json'], checkOnSave: false, cargo: { buildScripts: { enable: false } }, procMacro: { enable: false }, rustfmt: {extraArgs: ['--config-path', '.']} } } });
send({ jsonrpc: '2.0', method: 'initialized', params: {} });
const uri = 'file:///ws/main.rs';
send({ jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: { uri, languageId: 'rust', version: 1, text: text(1) } } });
for (let i = 2; i < 8; i++) {
	await new Promise((r) => setTimeout(r, 400));
	send({ jsonrpc: '2.0', method: 'textDocument/didChange', params: { textDocument: { uri, version: i }, contentChanges: [{ text: text(i) }] } });
}
const deadline = Date.now() + 120000;
while (!sawError && exitCode === undefined && Date.now() < deadline) await new Promise((r) => setTimeout(r, 200));
assert(sawError, 'lsp gate: no E0308 diagnostic');
const source = 'const LABEL: &str = "🦀";\n\nasync fn main(){let café=1;println!("{LABEL} {café}");}\n';
const expected = 'const LABEL: &str = "🦀";\n\nasync fn main() {\n\tlet café = 1;\n\tprintln!("{LABEL} {café}");\n}\n';
let version = 8;
const format = async (text) => {
	send({jsonrpc: '2.0', method: 'textDocument/didChange', params: {textDocument: {uri, version: version++}, contentChanges: [{text}]}});
	return request('textDocument/formatting', {textDocument: {uri}, options: {tabSize: 4, insertSpaces: false}});
};
const edits = await format(source);
assert(edits.every((edit) => edit.range.start.line >= 2), 'formatting must leave the unchanged prefix outside its edits');
const offset = ({line, character}) => source.split('\n').slice(0, line).reduce((n, s) => n + s.length + 1, 0) + character;
let formatted = source;
for (const edit of edits.toSorted((a, b) => offset(b.range.start) - offset(a.range.start))) {
	formatted = formatted.slice(0, offset(edit.range.start)) + edit.newText + formatted.slice(offset(edit.range.end));
}
assert.equal(formatted, expected);
assert.deepEqual((await format(formatted)) ?? [], []);
assert.deepEqual((await format('fn main( {\n')) ?? [], []);
assert.deepEqual(await format(source), edits);
console.log('lsp gate (formatting, config, edition, Unicode, minimal edits, invalid-source recovery): ok');
await request('shutdown');
send({ jsonrpc: '2.0', method: 'exit' });
await new Promise((r) => setTimeout(r, 1000));
console.log('lsp gate (edits during analysis): ok');
