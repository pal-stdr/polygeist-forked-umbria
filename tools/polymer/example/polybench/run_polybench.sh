#!/bin/bash

SOURCE_DIR="$1"
OUTPUT_DIR="$2"

LLVM_BINDIR="${PWD}/../../llvm/build/bin"
BINDIR="${PWD}/../../build/bin"

TOTAL_CASES=0
SUCCESSFUL_CASES=0

execute()
{
    local MLIR_FILE="$1"
    local OUT_FILE="$2"

    # Run the compiled MLIR code by lli.
    "${LLVM_BINDIR}/mlir-opt" "${MLIR_FILE}" -lower-affine -convert-scf-to-std -canonicalize -convert-std-to-llvm |\
    "${LLVM_BINDIR}/mlir-translate" -mlir-to-llvmir |\
    "${LLVM_BINDIR}/opt" -O3 -march=native |\
    "${LLVM_BINDIR}/lli" 2>&1 | tee "${OUT_FILE}" &>/dev/null
}

compare_result()
{
  local SRC_FILE="$1"
  local DST_FILE="$2"
  local OUT_DIR=$(dirname "${DST_FILE}")

  local SRC_BASE=$(basename "${SRC_FILE}")
  local DST_BASE=$(basename "${DST_FILE}")

  execute "${SRC_FILE}" "${OUT_DIR}/${SRC_BASE}.out"
  execute "${DST_FILE}" "${OUT_DIR}/${DST_BASE}.out"

  diff "${OUT_DIR}/${SRC_BASE}.out" "${OUT_DIR}/${DST_BASE}.out" 2>&1 >/dev/null

  local DIFF_RETVAL=$?
  return "${DIFF_RETVAL}"
}


cd ${PWD}/../../build && ninja && cd -

printf "%40s %15s %15s %15s\n" "Benchmark" "Exit code" "Scop Diff" "Pluto Diff"
printf "%40s %15s %15s %15s\n" "--------------------------------" "-------------" "-------------" "-------------"

for f in $(find "${SOURCE_DIR}" -name "*.mlir.ll"); do
  mv $f ${f%.ll}
done

for f in $(find "${SOURCE_DIR}" -name "*.mlir"); do
  DIRNAME=$(dirname "${f}")
  BASENAME=$(basename "${f}")
  NAME="${BASENAME%.*}"

  OUT_DIR="${OUTPUT_DIR}/${DIRNAME}/${NAME}"
  SRC_FILE="${OUT_DIR}/${NAME}.mlir"
  SCOP_FILE="${OUT_DIR}/${NAME}.scop.mlir"
  PLUTO_FILE="${OUT_DIR}/${NAME}.pluto.mlir"

  # Where the output result will be generated to.
  mkdir -p "${OUT_DIR}"

  "${BINDIR}/polymer-opt" "$f" 2>/dev/null | tee "${SRC_FILE}" >/dev/null
  "${BINDIR}/polymer-opt" -reg2mem -extract-scop-stmt -canonicalize "$f" 2>/dev/null | tee "${SCOP_FILE}" >/dev/null
  # The optimization command
  "${BINDIR}/polymer-opt" \
    -reg2mem \
    -extract-scop-stmt \
    -pluto-opt \
    -canonicalize \
    "$f" 2>/dev/null | "${BINDIR}/polymer-opt" | tee "${PLUTO_FILE}" >/dev/null
  EXIT_STATUS="${PIPESTATUS[0]}"

  # Report
  compare_result "${SRC_FILE}" "${SCOP_FILE}"
  SCOP_RETVAL=$?
  compare_result "${SRC_FILE}" "${PLUTO_FILE}"
  PLUTO_RETVAL=$?

  printf "%40s %15d %15d %15d\n" "${f}" "${EXIT_STATUS}" "${SCOP_RETVAL}" "${PLUTO_RETVAL}"

  ((TOTAL_CASES=TOTAL_CASES+1))
  if [[ ${EXIT_STATUS} -eq 0 && ${SCOP_RETVAL} -eq 0 && ${PLUTO_RETVAL} -eq 0 ]]; then
    ((SUCCESSFUL_CASES=SUCCESSFUL_CASES+1))
  fi

done

echo ""
printf "%50s\n" "Report:"
printf "%50s %5d\n" "Total cases:" "${TOTAL_CASES}"
printf "%50s %5d\n" "Successful cases:" "${SUCCESSFUL_CASES}"
