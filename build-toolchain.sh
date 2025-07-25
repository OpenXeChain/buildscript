#!/usr/bin/env bash

# Build script for the OpenXeChain toolchain project
#
# Copyright (c) 2025 Aiden Isik
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# ANSI colour escape codes
ANSI_RED="\033[31m"
ANSI_GRN="\033[32m"
ANSI_CLR="\033[0m"

# Toolchain name
TOOLCHAIN_NAME="OpenXeChain"
TOOLCHAIN_STEM="${ANSI_GRN}${TOOLCHAIN_NAME}${ANSI_CLR}> "

# User-configurable variables
PREFIX="$(realpath ${PREFIX:-sysroot})" # Sysroot for the toolchain to be installed into
HOST_CC="${HOST_CC:-clang}" # Host compiler to use (MUST BE CLANG)
HOST_CXX="${HOST_CXX:-clang++}"
BUILD_TYPE="${BUILD_TYPE:-Release}" # Debug level to build LLVM in
PARALLEL="${PARALLEL:-$(nproc)}" # Number of parallel make jobs to run

# Static variables
LLVM_TARGET="ppc32-xbox360"
NEWLIB_TARGET="ppc-xbox360"
OLD_PWD="${PWD}"

# Build log path
BUILD_LOG="${OLD_PWD}/build.log"
echo "" > "${BUILD_LOG}" # Delete the old logs, if they exist

# If we fail to build, run this
fail_build()
{
    echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Failed to build! Check build.log.${ANSI_CLR}"
    exit 1
}

# Check to make sure all required dependencies are installed
check_deps()
{
    MISSING_DEPS=0

    clang --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing clang!${ANSI_CLR}")

    ar --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing binutils!${ANSI_CLR}")

    git --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing git!${ANSI_CLR}")

    cmake --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing cmake!${ANSI_CLR}")

    make --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing make!${ANSI_CLR}")

    ninja --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing ninja!${ANSI_CLR}")

    python3 --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing python3!${ANSI_CLR}")

    bash --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing bash!${ANSI_CLR}")

    bzip2 --help >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing bzip2!${ANSI_CLR}")

    gzip --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing gzip!${ANSI_CLR}")

    grep --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing grep!${ANSI_CLR}")

    xargs --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing findutils!${ANSI_CLR}")

    sed --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing sed!${ANSI_CLR}")

    tar --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing tar!${ANSI_CLR}")

    unzip --help >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing unzip!${ANSI_CLR}")

    zip --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing zip!${ANSI_CLR}")

    gawk --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing gawk!${ANSI_CLR}")

    # Zlib cannot be checked like this as it has no binaries, but it should have been installed
    # as a dependency of python3

    # Check for pyyaml with a simple python script
    cat > "test-pyyaml-openxechain.py" << EOF
import importlib.util
pyyaml_test=importlib.util.find_spec('yaml')
if pyyaml_test is None:
        exit(1)
else:
        exit(0)
EOF

    python3 test-pyyaml-openxechain.py >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing python-pyyaml!${ANSI_CLR}")

    rm -f test-pyyaml-openxechain.py

    if [[ ${MISSING_DEPS} -ne 0 ]]; then
        echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Dependencies are missing! Please install them.${ANSI_CLR}"
    fi

    return ${MISSING_DEPS}
}

cd "$(dirname $0)" || fail_build

if [[ ! -d "newlib" || ! -d "llvm" || ! -d "synthxex" || ! -d "xecorelib" ]]; then
    echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Submodules are missing! Please re-clone this repository with --recursive.${ANSI_CLR}"
    fail_build
fi

# Create the sysroot directory, if it doesn't already exist
echo -e "${TOOLCHAIN_STEM}Creating sysroot directory \"${PREFIX}\"."
mkdir -pv "${PREFIX}" >> "${BUILD_LOG}" 2>&1 || fail_build

# Make sure all required dependencies are installed
echo -e "${TOOLCHAIN_STEM}Checking if required dependencies are installed."
mkdir -pv "build" >> "${BUILD_LOG}" 2>&1 || fail_build
cd "build" || fail_build
check_deps || fail_build

# Configure it first
echo -e "${TOOLCHAIN_STEM}Configuring the cross compiler... (this may take a while)"
cmake -DCMAKE_C_COMPILER="${HOST_CC}" \
      -DCMAKE_CXX_COMPILER="${HOST_CXX}" \
      -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
      -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
      -DLLVM_ENABLE_PROJECTS="lld;clang" \
      -DLLVM_TARGETS_TO_BUILD=PowerPC \
      -DLLVM_DEFAULT_TARGET_TRIPLE="${LLVM_TARGET}" \
      -DLLVM_INSTALL_BINUTILS_SYMLINKS=true \
      -DLLVM_INSTALL_CCTOOLS_SYMLINKS=true \
      -DLLVM_INSTALL_TOOLCHAIN_ONLY=true \
      -G "Ninja" ../llvm/llvm >> "${BUILD_LOG}" 2>&1 || fail_build

# Now build and install
echo -e "${TOOLCHAIN_STEM}Building the cross compiler... (this may take a WHILE)"
ninja -j${PARALLEL} >> "${BUILD_LOG}" 2>&1 || fail_build

echo -e "${TOOLCHAIN_STEM}Installing the cross compiler... (this may take a while)"
ninja install >> "${BUILD_LOG}" 2>&1 || fail_build

echo -e "${TOOLCHAIN_STEM}Cross compiler built and installed!"
rm -rf * # Clear the build directory, ready for xecorelib

# Define the default command line flags to be used by the cross-compiler.
# Linkage to Newlib/xecorelib is also added to these files, but after it's been built and installed.
echo -e "${TOOLCHAIN_STEM}Writing initial Clang configuration scripts."

cat > "${PREFIX}/bin/clang.cfg" << EOF
-Wno-main-return-type
--sysroot=<CFGDIR>/..
--rtlib=compiler-rt
-fdeclspec
EOF

cat > "${PREFIX}/bin/clang++.cfg" << EOF
-Wno-main-return-type
--sysroot=<CFGDIR>/..
--rtlib=compiler-rt
-fdeclspec
EOF

# Clear the environment variables the C/C++ compiler is sensitive to,
# to avoid pollution.
# We restore them later.
OLD_LIBRARY_PATH="${LIBRARY_PATH}"
OLD_C_INCLUDE_PATH="${C_INCLUDE_PATH}"
OLD_CPLUS_INCLUDE_PATH="${CPLUS_INCLUDE_PATH}"
export LIBRARY_PATH=""
export C_INCLUDE_PATH=""
export CPLUS_INCLUDE_PATH=""

# Build xecorelib
echo -e "${TOOLCHAIN_STEM}Building and installing xecorelib."

# Run the xecorelib build script
PREFIX="${PREFIX}" bash ../xecorelib/install.sh >> "${BUILD_LOG}" 2>&1 || fail_build

# Also install to PWD, to build Newlib with it
BINDIR="${PREFIX}/bin" PREFIX="${PWD}/xecorelibtmp" bash ../xecorelib/install.sh >> "${BUILD_LOG}" 2>&1 || fail_build
echo -e "${TOOLCHAIN_STEM}Built and installed xecorelib!"

# Clear the build directory, ready for Newlib
ls | grep -P "^(?!xecorelibtmp$).*$" | xargs -d"\n" rm -rf

# Build the Newlib libc
echo -e "${TOOLCHAIN_STEM}Getting ready to build the Newlib C library."

# Configure Newlib
echo -e "${TOOLCHAIN_STEM}Configuring the Newlib C library... (this may take a while)"

../newlib/newlib/configure \
    CC="${PREFIX}/bin/clang -nostdlib -I${PWD}/xecorelibtmp/include" \
    CPP="${PREFIX}/bin/clang-cpp" \
    LD="${PREFIX}/bin/lld-link" \
    AR="${PREFIX}/bin/llvm-ar" \
    AS="${PREFIX}/bin/llvm-as" \
    STRIP="${PREFIX}/bin/llvm-strip" \
    RANLIB="${PREFIX}/bin/llvm-ranlib" \
    --prefix="${PREFIX}" \
    --host="${NEWLIB_TARGET}" \
    --target="${NEWLIB_TARGET}" \
    --enable-newlib-supplied-syscalls=yes \
    --enable-newlib-mb \
    --enable-newlib-iconv >> "${BUILD_LOG}" 2>&1 || fail_build

# Now build and install
echo -e "${TOOLCHAIN_STEM}Building the Newlib C library..."
make -j${PARALLEL} >> "${BUILD_LOG}" 2>&1 || fail_build

echo -e "${TOOLCHAIN_STEM}Installing the Newlib C library..."
make install >> "${BUILD_LOG}" 2>&1 || fail_build

# Add Newlib/xecorelib linkage to the default compiler flags now that it is installed
echo -e "${TOOLCHAIN_STEM}Adding Newlib linkage to Clang configuration scripts."

cat >> "${PREFIX}/bin/clang.cfg" << EOF
-isystem <CFGDIR>/../${NEWLIB_TARGET}/include
-isystem <CFGDIR>/../include
-Wl,/libpath:<CFGDIR>/../${NEWLIB_TARGET}/lib,/libpath:<CFGDIR>/../lib
-Wl,/defaultlib:xecorelib.a,/defaultlib:libc.a
EOF

cat >> "${PREFIX}/bin/clang++.cfg" << EOF
-isystem <CFGDIR>/../${NEWLIB_TARGET}/include
-isystem <CFGDIR>/../include
-Wl,/libpath:<CFGDIR>/../${NEWLIB_TARGET}/lib,/libpath:<CFGDIR>/../lib
-Wl,/defaultlib:xecorelib.a,/defaultlib:libc.a
EOF

echo -e "${TOOLCHAIN_STEM}Newlib C library built and installed!"
rm -rf * # Clear the build directory, ready for compiler-rt

# Configure compiler-rt
# We need to override the compiler checks, otherwise CMake will attempt to
# build test programs, which won't work, as it'll try to link compiler-rt,
# which is not yet installed.
echo -e "${TOOLCHAIN_STEM}Configuring compiler-rt..."
cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
      -DCMAKE_SYSTEM_NAME="Generic" \
      -DCMAKE_CROSSCOMPILING=true \
      -DCMAKE_C_COMPILER="${PREFIX}/bin/clang" \
      -DCMAKE_CXX_COMPILER="${PREFIX}/bin/clang++" \
      -DCMAKE_AR="${PREFIX}/bin/llvm-ar" \
      -DCMAKE_LINKER="${PREFIX}/bin/lld-link" \
      -DCMAKE_RANLIB="${PREFIX}/bin/llvm-ranlib" \
      -DCMAKE_SYSROOT="${PREFIX}" \
      -DCMAKE_C_COMPILER_WORKS=true \
      -DCMAKE_CXX_COMPILER_WORKS=true \
      -DCMAKE_C_COMPILER_TARGET="ppc32-xbox360" \
      -DCOMPILER_RT_BUILD_BUILTINS=true \
      -DCOMPILER_RT_DEFAULT_TARGET_ONLY=true \
      -DCOMPILER_RT_BUILD_SANITIZERS=false \
      -DCOMPILER_RT_BUILD_XRAY=false \
      -DCOMPILER_RT_BUILD_LIBFUZZER=false \
      -DCOMPILER_RT_BUILD_PROFILE=false \
      -DCOMPILER_RT_STANDALONE_BUILD=true \
      -DCOMPILER_RT_BUILTINS_ENABLE_PIC=false \
      -DCOMPILER_RT_BAREMETAL_BUILD=true \
      -G "Ninja" ../llvm/compiler-rt >> "${BUILD_LOG}" 2>&1 || fail_build

# Now build and install
echo -e "${TOOLCHAIN_STEM}Building compiler-rt..."
ninja -j${PARALLEL} >> "${BUILD_LOG}" 2>&1 || fail_build

echo -e "${TOOLCHAIN_STEM}Installing compiler-rt..."
ninja install >> "${BUILD_LOG}" 2>&1 || fail_build

# Add compiler-rt linkage to Clang config scripts
echo -e "${TOOLCHAIN_STEM}Adding compiler-rt linkage to Clang configuration scripts."

cat >> "${PREFIX}/bin/clang.cfg" << EOF
-Wl,/libpath:<CFGDIR>/../lib/generic
-Wl,/defaultlib:libclang_rt.builtins-powerpc.a
EOF

cat >> "${PREFIX}/bin/clang++.cfg" << EOF
-Wl,/libpath:<CFGDIR>/../lib/generic
-Wl,/defaultlib:libclang_rt.builtins-powerpc.a
EOF

echo -e "${TOOLCHAIN_STEM}Compiler-rt built and installed!"
rm -rf * # Clear the build directory, ready for SynthXEX

# Restore the environment variables the C/C++ compiler is sensitive to
export LIBRARY_PATH="${OLD_LIBRARY_PATH}"
export C_INCLUDE_PATH="${OLD_C_INCLUDE_PATH}"
export CPLUS_INCLUDE_PATH="${OLD_CPLUS_INCLUDE_PATH}"

# Build SynthXEX
echo -e "${TOOLCHAIN_STEM}Getting ready to build SynthXEX."

# Configure SynthXEX
echo -e "${TOOLCHAIN_STEM}Configuring SynthXEX..."

cmake -DCMAKE_C_COMPILER="${HOST_CC}" \
      -DCMAKE_CXX_COMPILER="${HOST_CXX}" \
      -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
      -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
      -G "Ninja" ../synthxex >> "${BUILD_LOG}" 2>&1 || fail_build

# Now build and install
echo -e "${TOOLCHAIN_STEM}Building SynthXEX..."
ninja -j${PARALLEL} >> "${BUILD_LOG}" 2>&1 || fail_build

echo -e "${TOOLCHAIN_STEM}Installing SynthXEX..."
ninja install >> "${BUILD_LOG}" 2>&1 || fail_build

echo -e "${TOOLCHAIN_STEM}SynthXEX built and installed!"

# Finished
echo -e "${TOOLCHAIN_STEM}${ANSI_GRN}${TOOLCHAIN_NAME} has been built successfully.${ANSI_CLR}"
echo -e "${TOOLCHAIN_STEM}${ANSI_GRN}Current installled location: ${PREFIX}.${ANSI_CLR}"
echo -e "${TOOLCHAIN_STEM}${ANSI_GRN}This toolchain is portable, it can be moved to any path and still work.${ANSI_CLR}"
echo -e "${TOOLCHAIN_STEM}${ANSI_GRN}Ensure C_INCLUDE_PATH, CPLUS_INCLUDE_PATH, and LIBRARY_PATH${ANSI_CLR}"
echo -e "${TOOLCHAIN_STEM}${ANSI_GRN}are set blank when using the toolchain, or you may encounter${ANSI_CLR}"
echo -e "${TOOLCHAIN_STEM}${ANSI_GRN}interference from the host libraries.${ANSI_CLR}"

cd ..
rm -rf build
rm -f build.log
