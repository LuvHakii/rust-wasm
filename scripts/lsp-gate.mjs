// edits that land while the first analysis is still running used to abort the server (salsa cancels by unwinding)
import { spawn } from 'node:child_process';

const [wasmtime, wasm, dir] = process.argv.slice(2);
const text = (n) => `use std::collections::HashMap;\nfn main() {\n    let mut m: HashMap<String, i32> = HashMap::new();\n    m.insert("a".to_string(), ${n});\n    let x: i32 = "oops";\n}\n`;
const p = spawn(wasmtime, ['run', '-W', 'threads=y', '-S', 'threads=y', '--dir', `${dir}::/`, wasm], { stdio: ['pipe', 'pipe', 'inherit'] });
const send = (o) => { const s = JSON.stringify(o); p.stdin.write(`Content-Length: ${Buffer.byteLength(s)}\r\n\r\n${s}`); };
let buf = Buffer.alloc(0);
let sawError = false;
let exitCode;
p.on('exit', (c) => { exitCode = c; });
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
	}
});
send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { processId: null, rootUri: 'file:///ws', capabilities: {}, initializationOptions: { linkedProjects: ['/ws/rust-project.json'], checkOnSave: false, cargo: { buildScripts: { enable: false } }, procMacro: { enable: false } } } });
send({ jsonrpc: '2.0', method: 'initialized', params: {} });
const uri = 'file:///ws/main.rs';
send({ jsonrpc: '2.0', method: 'textDocument/didOpen', params: { textDocument: { uri, languageId: 'rust', version: 1, text: text(1) } } });
for (let i = 2; i < 8; i++) {
	await new Promise((r) => setTimeout(r, 400));
	send({ jsonrpc: '2.0', method: 'textDocument/didChange', params: { textDocument: { uri, version: i }, contentChanges: [{ text: text(i) }] } });
}
const deadline = Date.now() + 120000;
while (!sawError && exitCode === undefined && Date.now() < deadline) await new Promise((r) => setTimeout(r, 200));
send({ jsonrpc: '2.0', id: 2, method: 'shutdown' });
send({ jsonrpc: '2.0', method: 'exit' });
await new Promise((r) => setTimeout(r, 1000));
if (!sawError) {
	console.error(`lsp gate: no E0308 diagnostic (server exit code ${exitCode})`);
	process.exit(1);
}
console.log('lsp gate (edits during analysis): ok');
