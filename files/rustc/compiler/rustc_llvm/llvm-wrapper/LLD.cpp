#include <vector>

#include "lld/Common/Driver.h"

LLD_HAS_DRIVER(wasm)

extern "C" int RustRunLld(int argc, char **argv) {
    std::vector<const char *> args(argv, argv + argc);
    args.push_back("--threads=1");
    auto r = lld::lldMain(args, llvm::outs(), llvm::errs(), {{lld::Wasm, &lld::wasm::link}});
    return r.retCode;
}
