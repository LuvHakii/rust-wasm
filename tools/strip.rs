// usage: strip <expanded.rs> <out-dir>
// Trims what rust-analyzer does not need, then splits inline modules back into files named like the originals
// (`mod iter { mod traits { .. } }` -> iter.rs, iter/traits.rs) so go-to-definition lands in a file with the right name.
use std::{
    fs,
    path::{Path, PathBuf},
};
use syntax::{ast::{self, HasAttrs, HasName, HasVisibility}, AstNode, Edition, SourceFile, SyntaxKind, SyntaxNode, TextRange, TextSize};

// Attributes rust-analyzer never reads: stability bookkeeping and codegen hints.
const DROP_ATTRS: &[&str] = &["stable", "rustc_const_stable", "rustc_const_unstable", "inline", "track_caller", "rustc_inherit_overflow_checks", "rustc_allow_const_fn_unstable"];

// Replacement ranges: fn bodies nobody can navigate to or that inference never needs (private fns outside trait impls/traits;
// kept: pub fns, trait impl methods, trait defaults, const fns for const eval, fns returning `impl Trait` which is inferred from the body),
// and the attributes above. Doc examples stay: dropping them halves hover text and saves under 2% CPU.
fn trim(text: &str) -> (String, usize, usize) {
    let parse = SourceFile::parse(text, Edition::Edition2024);
    let root = parse.tree();
    let mut edits: Vec<(usize, usize, &str)> = vec![];
    let (mut bodies, mut attrs) = (0, 0);
    for f in root.syntax().descendants().filter_map(ast::Fn::cast) {
        let Some(body) = f.body() else { continue };
        if f.visibility().is_some_and(|v| v.syntax().text() == "pub") || f.const_token().is_some() || f.async_token().is_some() {
            continue;
        }
        if f.ret_type().is_some_and(|r| r.syntax().descendants().any(|n| ast::ImplTraitType::can_cast(n.kind()))) {
            continue;
        }
        let in_trait_like = f.syntax().parent().and_then(|p| p.parent()).is_some_and(|g| ast::Trait::can_cast(g.kind()) || ast::Impl::cast(g).is_some_and(|i| i.trait_().is_some()));
        if in_trait_like {
            continue;
        }
        let r = body.syntax().text_range();
        let (s, e) = (usize::from(r.start()), usize::from(r.end()));
        if e - s > 12 {
            edits.push((s, e, "{ loop {} }"));
            bodies += 1;
        }
    }
    for attr in root.syntax().descendants().filter_map(ast::Attr::cast) {
        if attr.excl_token().is_none() && attr.path().is_some_and(|p| DROP_ATTRS.contains(&p.to_string().as_str())) {
            let r = attr.syntax().text_range();
            let s = usize::from(r.start());
            let mut e = usize::from(r.end());
            e += text[e..].len() - text[e..].trim_start().len();
            edits.push((s, e, ""));
            attrs += 1;
        }
    }
    edits.sort_by_key(|&(s, e, _)| (s, std::cmp::Reverse(e)));
    let mut out = String::with_capacity(text.len());
    let mut pos = 0;
    for (s, e, with) in edits {
        if s < pos {
            continue;
        }
        out.push_str(&text[pos..s]);
        out.push_str(with);
        pos = e;
    }
    out.push_str(&text[pos..]);
    (out, bodies, attrs)
}

fn render(container: &SyntaxNode, inner: TextRange, text: &str, dir: &Path, files: &mut usize) -> String {
    let mut children: Vec<ast::Module> = container.children().filter_map(ast::Module::cast).filter(|m| m.item_list().is_some()).collect();
    children.sort_by_key(|m| m.syntax().text_range().start());
    let mut out = String::new();
    let mut pos = usize::from(inner.start());
    for m in children {
        let list = m.item_list().unwrap();
        let (m_start, l_start) = (usize::from(m.syntax().text_range().start()), usize::from(list.syntax().text_range().start()));
        let l_curly = list.l_curly_token().unwrap().text_range();
        let r_curly = list.r_curly_token().unwrap().text_range();
        let name = m.name().unwrap().text().trim_start_matches("r#").to_string();
        let inner_range = TextRange::new(l_curly.end(), r_curly.start());
        let body = render(list.syntax(), inner_range, text, &dir.join(&name), files);
        fs::create_dir_all(dir).unwrap();
        fs::write(dir.join(format!("{name}.rs")), body).unwrap();
        *files += 1;
        out.push_str(&text[pos..m_start]);
        out.push_str(text[m_start..l_start].trim_end());
        out.push(';');
        pos = usize::from(m.syntax().text_range().end());
    }
    out.push_str(&text[pos..usize::from(inner.end())]);
    out
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let text = fs::read_to_string(&a[1]).unwrap();
    let (stripped, fns, attrs) = trim(&text);
    let parse = SourceFile::parse(&stripped, Edition::Edition2024);
    let root = parse.tree();
    let dir = PathBuf::from(&a[2]);
    fs::create_dir_all(&dir).unwrap();
    let whole = TextRange::new(TextSize::from(0), TextSize::from(stripped.len() as u32));
    let mut files = 1;
    let lib = render(root.syntax(), whole, &stripped, &dir, &mut files);
    fs::write(dir.join("lib.rs"), lib).unwrap();
    println!("{fns} private fn bodies, {attrs} attrs dropped: {} -> {} bytes in {files} files, {} parse errors", text.len(), stripped.len(), parse.errors().len());
}
