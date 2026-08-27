#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_NAME="$(basename "${SCRIPT_DIR}")"
PROJECT_NAME="${PROJECT_NAME#docs-}"
MANUAL_DIR="${SCRIPT_DIR}/manual"
MANUAL_SRC_DIR="${MANUAL_DIR}/src"
MANUAL_SUPPORT_DIR="${MANUAL_DIR}/support"
BUILD_DIR="${SCRIPT_DIR}/build"
WRAPPER_DIR="${SCRIPT_DIR}/.render_wrappers"
OUTPUT_DIR="${SCRIPT_DIR}/pdf"
CURRENT_OUTPUT_DIR="${DOCS_ROOT_DIR}/current_pdfs"
LATEX_TEXINPUTS="${DOCS_ROOT_DIR}/tools/latex//:${MANUAL_SUPPORT_DIR}//:${MANUAL_SRC_DIR}//:${SCRIPT_DIR}//:"
NUMBERED_SUFFIX="_numbered"
COMBINED_OUTPUT_FILE="${OUTPUT_DIR}/${PROJECT_NAME}_docs_combined_compact.pdf"
COMBINED_DOCS_ONLY_FILE="${BUILD_DIR}/docs_combined_compact_docs_only.pdf"
COMBINED_NUMBERED_OUTPUT_FILE="${OUTPUT_DIR}/${PROJECT_NAME}_docs_combined_compact${NUMBERED_SUFFIX}.pdf"
COMBINED_NUMBERED_DOCS_ONLY_FILE="${BUILD_DIR}/docs_combined_compact_docs_only${NUMBERED_SUFFIX}.pdf"
CURRENT_COMBINED_OUTPUT_FILE="${CURRENT_OUTPUT_DIR}/${PROJECT_NAME}.pdf"
DRIVE_TARGET_RELATIVE="My Drive/android_pdf"
INDEX_SOURCE_FILE="${MANUAL_SRC_DIR}/documentation_index.tex"
INDEX_OVERRIDES_FILE="${BUILD_DIR}/documentation_index_page_overrides.tex"
DOC_ORDER_MANIFEST="${MANUAL_DIR}/docs_order_manifest.txt"
STANDALONE_APPENDIX_FILE="appendix_extended_related_work.tex"
COMBINED_INCLUDE_FILE="${BUILD_DIR}/docs_combined_manifest_inputs.tex"
LAYOUT_CONFIG_FILE="${MANUAL_SUPPORT_DIR}/manual_docs_layout_config.tex"
BIB_COMPAT_DIR="${BUILD_DIR}/bibinputs"
LEFT_PADDING_DELTA="0pt"
RIGHT_PADDING_DELTA="0pt"
NIPS_LEFT_PADDING_DELTA="0pt"
NIPS_RIGHT_PADDING_DELTA="0pt"
NIPS_PROJECT_DIR="${SCRIPT_DIR}/overleaf_paper"
if [ ! -d "${NIPS_PROJECT_DIR}" ] && [ -d "${DOCS_ROOT_DIR}/docs-TraceBench-paper" ]; then
  NIPS_PROJECT_DIR="${DOCS_ROOT_DIR}/docs-TraceBench-paper"
fi
NIPS_BUILD_SCRIPT="${NIPS_PROJECT_DIR}/build.sh"
NIPS_MAIN_PDF="${NIPS_PROJECT_DIR}/archive/compiled/main.pdf"
NIPS_MAIN_AUX="${NIPS_PROJECT_DIR}/build/main.aux"
NIPS_REFERENCES_BIB="${NIPS_PROJECT_DIR}/tex/support/references.bib"
LATEX_BIBINPUTS="${BIB_COMPAT_DIR}:${NIPS_PROJECT_DIR}:${SCRIPT_DIR}:"
BUILD_COMBINED=false
FORCE_REBUILD=false
SKIP_PAPER=false
SYNC_TO_DRIVE=false
built_pdfs=()

usage() {
  cat <<EOF
Usage: ./render_all_pdf.sh [options]

Incrementally build standalone docs PDFs and the NIPS manuscript. Combined PDFs are only rebuilt when requested.

Options:
  --left-padding <delta>   Relative adjustment from the default 1in left margin.
  --right-padding <delta>  Relative adjustment from the default 1in right margin.
  --nips-left-padding <delta>   Relative adjustment for the NIPS manuscript left margin.
  --nips-right-padding <delta>  Relative adjustment for the NIPS manuscript right margin.
  --combine                Rebuild and merge the combined manual PDFs.
  --skip-paper             Build only the standalone docs and never invoke the NIPS build.
  --force                  Delete target build artifacts before compiling.
  --all                    Shortcut for --combine --force.
  --sync_to_drive          Update existing built PDFs in My Drive/android_pdf.
  --help                   Show this help message.

Examples:
  ./render_all_pdf.sh
  ./render_all_pdf.sh --skip-paper
  ./render_all_pdf.sh --combine
  ./render_all_pdf.sh --skip-paper --combine
  ./render_all_pdf.sh --sync_to_drive
  ./render_all_pdf.sh --all
  ./render_all_pdf.sh --left-padding +0.2in --right-padding 0pt
  ./render_all_pdf.sh --left-padding -6pt --right-padding +12pt
  ./render_all_pdf.sh --combine --left-padding -25mm --right-padding +25mm --nips-left-padding 0pt --nips-right-padding +10mm
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --left-padding)
      if [ "$#" -lt 2 ] || [[ "$2" == --* ]]; then
        echo "Error: --left-padding requires a value." >&2
        usage >&2
        exit 1
      fi
      LEFT_PADDING_DELTA="$2"
      shift 2
      ;;
    --right-padding)
      if [ "$#" -lt 2 ] || [[ "$2" == --* ]]; then
        echo "Error: --right-padding requires a value." >&2
        usage >&2
        exit 1
      fi
      RIGHT_PADDING_DELTA="$2"
      shift 2
      ;;
    --nips-left-padding)
      if [ "$#" -lt 2 ] || [[ "$2" == --* ]]; then
        echo "Error: --nips-left-padding requires a value." >&2
        usage >&2
        exit 1
      fi
      NIPS_LEFT_PADDING_DELTA="$2"
      shift 2
      ;;
    --nips-right-padding)
      if [ "$#" -lt 2 ] || [[ "$2" == --* ]]; then
        echo "Error: --nips-right-padding requires a value." >&2
        usage >&2
        exit 1
      fi
      NIPS_RIGHT_PADDING_DELTA="$2"
      shift 2
      ;;
    --combine)
      BUILD_COMBINED=true
      shift
      ;;
    --skip-paper)
      SKIP_PAPER=true
      shift
      ;;
    --force)
      FORCE_REBUILD=true
      shift
      ;;
    --all)
      BUILD_COMBINED=true
      FORCE_REBUILD=true
      shift
      ;;
    --sync_to_drive)
      SYNC_TO_DRIVE=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'." >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v latexmk >/dev/null 2>&1; then
  echo "Error: latexmk command not found." >&2
  exit 1
fi

if ! command -v pdflatex >/dev/null 2>&1; then
  echo "Error: pdflatex command not found." >&2
  exit 1
fi

if [ "${BUILD_COMBINED}" = "true" ] && ! command -v gs >/dev/null 2>&1; then
  echo "Error: gs command not found." >&2
  exit 1
fi

if [ ! -f "${INDEX_SOURCE_FILE}" ]; then
  echo "Error: index source file not found at ${INDEX_SOURCE_FILE}" >&2
  exit 1
fi

if [ "${SKIP_PAPER}" != "true" ] && { [ ! -f "${NIPS_BUILD_SCRIPT}" ] || [ ! -r "${NIPS_BUILD_SCRIPT}" ]; }; then
  echo "Error: NIPS build script not found or not readable at ${NIPS_BUILD_SCRIPT}" >&2
  exit 1
fi

shopt -s nullglob
tex_files=("${MANUAL_SRC_DIR}"/*.tex)
shopt -u nullglob

if [ "${#tex_files[@]}" -eq 0 ]; then
  echo "Error: no LaTeX files found in ${MANUAL_SRC_DIR}" >&2
  exit 1
fi

reconcile_doc_order_manifest() {
  local tex_file
  local tex_name
  local raw_line
  local temp_file
  local source_tex_names=()
  local existing_order=()
  local reconciled_order=()
  local source_registry=$'\n'
  local existing_registry=$'\n'

  for tex_file in "${tex_files[@]}"; do
    tex_name="$(basename "${tex_file}")"
    if [ "${tex_name}" = "documentation_index.tex" ] || [ "${tex_name}" = "docs_combined_compact.tex" ] || [ "${tex_name}" = "$(basename "${LAYOUT_CONFIG_FILE}")" ]; then
      continue
    fi
    case "${tex_name}" in
      appendix_*.tex)
        continue
        ;;
    esac
    source_tex_names+=("${tex_name}")
    source_registry+="${tex_name}"$'\n'
  done

  if [ "${#source_tex_names[@]}" -eq 0 ]; then
    echo "Error: no ordered document source files found in ${MANUAL_SRC_DIR}" >&2
    exit 1
  fi

  if [ -f "${DOC_ORDER_MANIFEST}" ]; then
    while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
      tex_name="${raw_line%$'\r'}"
      tex_name="${tex_name#"${tex_name%%[![:space:]]*}"}"
      tex_name="${tex_name%"${tex_name##*[![:space:]]}"}"

      if [ -z "${tex_name}" ] || [[ "${tex_name}" == \#* ]]; then
        continue
      fi

      case "${tex_name}" in
        /*|*../*|../*|*/*)
          echo "Error: ${DOC_ORDER_MANIFEST#${SCRIPT_DIR}/} entries must be .tex filenames under tex/source: ${tex_name}" >&2
          exit 1
          ;;
        *.tex)
          ;;
        *)
          echo "Error: ${DOC_ORDER_MANIFEST#${SCRIPT_DIR}/} entry is not a .tex file: ${tex_name}" >&2
          exit 1
          ;;
      esac

      if [ "${tex_name}" = "documentation_index.tex" ] || [ "${tex_name}" = "docs_combined_compact.tex" ] || [ "${tex_name}" = "$(basename "${LAYOUT_CONFIG_FILE}")" ]; then
        continue
      fi
      case "${tex_name}" in
        appendix_*.tex)
          continue
          ;;
      esac

      if [[ "${source_registry}" == *$'\n'"${tex_name}"$'\n'* ]] &&
        [[ "${existing_registry}" != *$'\n'"${tex_name}"$'\n'* ]]; then
        existing_order+=("${tex_name}")
        existing_registry+="${tex_name}"$'\n'
      fi
    done < "${DOC_ORDER_MANIFEST}"
  fi

  for tex_name in "${source_tex_names[@]}"; do
    if [[ "${existing_registry}" != *$'\n'"${tex_name}"$'\n'* ]]; then
      reconciled_order+=("${tex_name}")
    fi
  done
  if [ "${#existing_order[@]}" -gt 0 ]; then
    reconciled_order+=("${existing_order[@]}")
  fi

  temp_file="$(mktemp "${DOC_ORDER_MANIFEST}.tmp.XXXXXX")"
  {
    printf '# Canonical order for standalone docs included in the combined compact manual.\n'
    printf '# One .tex filename per line. Do not list documentation_index.tex,\n'
    printf '# docs_combined_compact.tex, or appendix_*.tex; the build handles those separately.\n'
    for tex_name in "${reconciled_order[@]}"; do
      printf '%s\n' "${tex_name}"
    done
  } > "${temp_file}"

  if [ -f "${DOC_ORDER_MANIFEST}" ] && cmp -s "${temp_file}" "${DOC_ORDER_MANIFEST}"; then
    rm -f "${temp_file}"
  else
    mv "${temp_file}" "${DOC_ORDER_MANIFEST}"
  fi
}

reconcile_doc_order_manifest

indexed_tex_files=()
while IFS= read -r tex_name || [ -n "${tex_name}" ]; do
  if [[ "${tex_name}" =~ ^[[:space:]]*$ ]] || [[ "${tex_name}" =~ ^[[:space:]]*# ]]; then
    continue
  fi
  indexed_tex_files+=("${tex_name}")
done < "${DOC_ORDER_MANIFEST}"

if [ "${#indexed_tex_files[@]}" -eq 0 ]; then
  echo "Error: no ordered document entries found in ${DOC_ORDER_MANIFEST}" >&2
  exit 1
fi

indexed_tex_registry=$'\n'
for tex_name in "${indexed_tex_files[@]}"; do
  if [[ "${indexed_tex_registry}" == *$'\n'"${tex_name}"$'\n'* ]]; then
    echo "Error: duplicate ordered document ${tex_name} in ${DOC_ORDER_MANIFEST}" >&2
    exit 1
  fi
  indexed_tex_registry+="${tex_name}"$'\n'

  if [ ! -f "${MANUAL_SRC_DIR}/${tex_name}" ]; then
    echo "Error: indexed document ${tex_name} does not exist in ${MANUAL_SRC_DIR}" >&2
    exit 1
  fi
done

unindexed_tex_files=()
for tex_file in "${tex_files[@]}"; do
  tex_name="$(basename "${tex_file}")"
  if [ "${tex_name}" = "documentation_index.tex" ] || [ "${tex_name}" = "docs_combined_compact.tex" ] || [ "${tex_name}" = "$(basename "${LAYOUT_CONFIG_FILE}")" ]; then
    continue
  fi
  case "${tex_name}" in
    appendix_*.tex)
      continue
      ;;
  esac
  if [[ "${indexed_tex_registry}" != *$'\n'"${tex_name}"$'\n'* ]]; then
    unindexed_tex_files+=("${tex_name}")
  fi
done

if [ "${#unindexed_tex_files[@]}" -gt 0 ]; then
  echo "Warning: unindexed LaTeX files will not be included in ${COMBINED_OUTPUT_FILE}:" >&2
  printf '  %s\n' "${unindexed_tex_files[@]}" >&2
fi

mkdir -p "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${WRAPPER_DIR}"
if [ -f "${NIPS_REFERENCES_BIB}" ]; then
  mkdir -p "${BIB_COMPAT_DIR}/overleaf_paper"
  if [ ! -f "${BIB_COMPAT_DIR}/overleaf_paper/tex/support/references.bib" ] ||
    ! cmp -s "${NIPS_REFERENCES_BIB}" "${BIB_COMPAT_DIR}/overleaf_paper/tex/support/references.bib"; then
    cp "${NIPS_REFERENCES_BIB}" "${BIB_COMPAT_DIR}/overleaf_paper/tex/support/references.bib"
  fi
fi

find_drive_target_dir() {
  local candidate
  shopt -s nullglob
  for candidate in "${HOME}/Library/CloudStorage"/GoogleDrive-*/"${DRIVE_TARGET_RELATIVE}"; do
    if [ -d "${candidate}" ]; then
      shopt -u nullglob
      printf '%s' "${candidate}"
      return 0
    fi
  done
  shopt -u nullglob

  candidate="${HOME}/Google Drive/${DRIVE_TARGET_RELATIVE}"
  if [ -d "${candidate}" ]; then
    printf '%s' "${candidate}"
    return 0
  fi

  return 1
}

register_built_pdf() {
  local pdf_file="$1"
  local existing

  case "${pdf_file}" in
    "${OUTPUT_DIR}"/*.pdf)
      ;;
    *)
      return 0
      ;;
  esac

  if [ "${#built_pdfs[@]}" -gt 0 ]; then
    for existing in "${built_pdfs[@]}"; do
      if [ "${existing}" = "${pdf_file}" ]; then
        return 0
      fi
    done
  fi
  built_pdfs+=("${pdf_file}")
}

sync_built_pdfs_to_drive() {
  local drive_target_dir
  local pdf_file
  local drive_pdf_file

  if ! drive_target_dir="$(find_drive_target_dir)"; then
    echo "Error: could not find Google Drive target folder '${DRIVE_TARGET_RELATIVE}'." >&2
    exit 1
  fi

  if [ "${#built_pdfs[@]}" -eq 0 ]; then
    return 0
  fi

  for pdf_file in "${built_pdfs[@]}"; do
    drive_pdf_file="${drive_target_dir}/$(basename "${pdf_file}")"
    if [ -f "${drive_pdf_file}" ]; then
      cp "${pdf_file}" "${drive_pdf_file}"
      echo "Synced: ${drive_pdf_file}"
    else
      echo "Skipped missing Drive file: ${drive_pdf_file}"
    fi
  done
}

finish() {
  if [ "${SYNC_TO_DRIVE}" = "true" ]; then
    sync_built_pdfs_to_drive
  fi
}

write_file_if_changed() {
  local target="$1"
  local temp_file

  temp_file="$(mktemp "${target}.tmp.XXXXXX")"
  cat > "${temp_file}"
  if [ -f "${target}" ] && cmp -s "${temp_file}" "${target}"; then
    rm -f "${temp_file}"
    return 0
  fi
  mv "${temp_file}" "${target}"
  return 0
}

cleanup_latexmk_target() {
  local stem="$1"
  local base="${BUILD_DIR}/${stem}"

  rm -f \
    "${base}.aux" \
    "${base}.bbl" \
    "${base}.blg" \
    "${base}.fdb_latexmk" \
    "${base}.fls" \
    "${base}.lof" \
    "${base}.log" \
    "${base}.lot" \
    "${base}.nav" \
    "${base}.out" \
    "${base}.pdf" \
    "${base}.run.xml" \
    "${base}.snm" \
    "${base}.synctex.gz" \
    "${base}.tex" \
    "${base}.toc" \
    "${base}.vrb"
}

write_layout_config() {
  write_file_if_changed "${LAYOUT_CONFIG_FILE}" <<EOF
% Generated by docs/render_all_pdf.sh. Direct docs builds inherit the last configured padding.
\providecommand{\manualDocLeftPaddingDelta}{${LEFT_PADDING_DELTA}}
\providecommand{\manualDocRightPaddingDelta}{${RIGHT_PADDING_DELTA}}
EOF
}

write_layout_config

generate_combined_include_file() {
  local tex_name=""
  local index=0
  local combined_tex_files=()
  local last_index
  local temp_file

  for tex_name in "${indexed_tex_files[@]}"; do
    case "${tex_name}" in
      appendix_*.tex)
        continue
        ;;
      *)
        combined_tex_files+=("${tex_name}")
        ;;
    esac
  done

  temp_file="$(mktemp "${COMBINED_INCLUDE_FILE}.tmp.XXXXXX")"
  {
    last_index=$((${#combined_tex_files[@]} - 1))
    for tex_name in "${combined_tex_files[@]}"; do
      printf '\\setManualDocSourceName{%s}\n' "${tex_name}"
      printf '\\input{../tex/source/%s}\n' "${tex_name}"
      if [ "${index}" -lt "${last_index}" ]; then
        printf '\\clearpage\n'
      fi
      index=$((index + 1))
    done
  } > "${temp_file}"
  if [ -f "${COMBINED_INCLUDE_FILE}" ] && cmp -s "${temp_file}" "${COMBINED_INCLUDE_FILE}"; then
    rm -f "${temp_file}"
  else
    mv "${temp_file}" "${COMBINED_INCLUDE_FILE}"
  fi
}

compile_tex() {
  local tex_name="$1"
  local output_stem="${2:-${tex_name%.tex}}"
  local source_file="${3:-${tex_name}}"
  local stem="${source_file##*/}"
  local display_source="${source_file}"
  stem="${stem%.tex}"
  local output_file="${OUTPUT_DIR}/${PROJECT_NAME}_${output_stem}.pdf"
  if [[ "${display_source}" == "${SCRIPT_DIR}/"* ]]; then
    display_source="${display_source#${SCRIPT_DIR}/}"
  fi
  echo "Compiling ${SCRIPT_DIR}/${display_source} -> ${output_file}"
  if [ "${FORCE_REBUILD}" = "true" ]; then
    cleanup_latexmk_target "${stem}"
  fi
  if ! (
    cd "${SCRIPT_DIR}"
    TEXINPUTS="${LATEX_TEXINPUTS}${TEXINPUTS:-}" \
      BIBINPUTS="${LATEX_BIBINPUTS}${BIBINPUTS:-}" \
      latexmk -pdf -interaction=nonstopmode -halt-on-error -file-line-error \
      -output-directory="${BUILD_DIR}" "${source_file}"
  ); then
    if [ -f "${BUILD_DIR}/${stem}.pdf" ]; then
      echo "Warning: latexmk returned nonzero for ${display_source}, but ${BUILD_DIR#${SCRIPT_DIR}/}/${stem}.pdf was produced." >&2
    else
      exit 1
    fi
  fi
  if [ ! -f "${BUILD_DIR}/${stem}.pdf" ]; then
    echo "Error: expected rendered PDF at ${BUILD_DIR}/${stem}.pdf" >&2
    exit 1
  fi
  copy_pdf_if_needed "${BUILD_DIR}/${stem}.pdf" "${output_file}"
}

create_build_wrapper() {
  local tex_name="$1"
  local output_var_name="$2"
  local wrapper_suffix="${3:-}"
  local enable_line_numbers="${4:-false}"
  local stem="${tex_name%.tex}"
  local wrapper_path="${WRAPPER_DIR}/${stem}${wrapper_suffix}.tex"

  {
    printf '\\def\\manualDocDefaultSourceBaseName{%s}\n' "${tex_name}"
    printf '\\def\\manualDocLeftPaddingDelta{%s}\n' "${LEFT_PADDING_DELTA}"
    printf '\\def\\manualDocRightPaddingDelta{%s}\n' "${RIGHT_PADDING_DELTA}"
    if [ "${enable_line_numbers}" = "true" ]; then
      printf '\\def\\manualDocEnableLineNumbers{1}\n'
    fi
    cat "${MANUAL_SRC_DIR}/${tex_name}"
  } | write_file_if_changed "${wrapper_path}"
  printf -v "${output_var_name}" '%s' "${wrapper_path}"
}

compile_tex_variants() {
  local tex_name="$1"
  local stem="${tex_name%.tex}"
  local normal_wrapper
  local numbered_wrapper

  create_build_wrapper "${tex_name}" normal_wrapper "" "false"
  compile_tex "${tex_name}" "${stem}" "${normal_wrapper}"

  create_build_wrapper "${tex_name}" numbered_wrapper "${NUMBERED_SUFFIX}" "true"
  compile_tex "${tex_name}" "${stem}${NUMBERED_SUFFIX}" "${numbered_wrapper}"
}

copy_rendered_pdf() {
  local rendered_stem="$1"
  local destination="$2"
  local rendered_pdf="${BUILD_DIR}/${rendered_stem}.pdf"

  if [ ! -f "${rendered_pdf}" ]; then
    echo "Error: expected rendered PDF at ${rendered_pdf}" >&2
    exit 1
  fi

  copy_pdf_if_needed "${rendered_pdf}" "${destination}"
}

copy_pdf_if_needed() {
  local source_pdf="$1"
  local destination="$2"

  if [ ! -f "${destination}" ] || ! cmp -s "${source_pdf}" "${destination}"; then
    cp "${source_pdf}" "${destination}"
  fi
  register_built_pdf "${destination}"
}

copy_current_combined_pdf() {
  if [ ! -f "${COMBINED_OUTPUT_FILE}" ]; then
    echo "Error: expected combined PDF at ${COMBINED_OUTPUT_FILE}" >&2
    exit 1
  fi

  mkdir -p "${CURRENT_OUTPUT_DIR}"
  copy_pdf_if_needed "${COMBINED_OUTPUT_FILE}" "${CURRENT_COMBINED_OUTPUT_FILE}"
  echo "Current combined PDF -> ${CURRENT_COMBINED_OUTPUT_FILE}"
}

build_nips_main() {
  echo "Building NIPS manuscript -> ${NIPS_MAIN_PDF}"
  local nips_args=(
    --left-padding "${NIPS_LEFT_PADDING_DELTA}"
    --right-padding "${NIPS_RIGHT_PADDING_DELTA}"
  )
  if [ "${FORCE_REBUILD}" = "true" ]; then
    nips_args+=(--force)
  fi
  bash "${NIPS_BUILD_SCRIPT}" \
    "${nips_args[@]}"

  if [ ! -f "${NIPS_MAIN_PDF}" ]; then
    echo "Error: expected NIPS manuscript PDF at ${NIPS_MAIN_PDF}" >&2
    exit 1
  fi
}

merge_pdfs() {
  local output_file="$1"
  shift

  echo "Merging PDFs -> ${output_file}"
  gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="${output_file}" "$@"
  register_built_pdf "${output_file}"
}

add_combined_index_paper_links() {
  local combined_pdf="$1"

  echo "Adding paper index links -> ${combined_pdf}"
  python3 - <<'PY' "${combined_pdf}" "${INDEX_OVERRIDES_FILE}" "${COMBINED_DOCS_ONLY_FILE}" "${NIPS_MAIN_AUX}"
from pathlib import Path
import re
import sys
from tempfile import NamedTemporaryFile

from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, DictionaryObject, FloatObject, NameObject, NullObject

pdf_path = Path(sys.argv[1])
overrides_path = Path(sys.argv[2])
docs_only_pdf = Path(sys.argv[3])
nips_aux = Path(sys.argv[4])

overrides = overrides_path.read_text()
page_values = {}
for name in ("manualDocPaperStartPage", "manualDocPaperAppendixStartPage"):
    match = re.search(rf"\\renewcommand\{{\\{name}\}}\{{([0-9]+)\}}", overrides)
    if match is not None:
        page_values[name] = int(match.group(1))

if len(page_values) != 2:
    docs_only_pages = len(PdfReader(str(docs_only_pdf)).pages)
    aux_text = nips_aux.read_text()
    appendix_match = re.search(r'\\newlabel\{docstart:nips_appendix\}\{\{[^}]*\}\{([^}]*)\}', aux_text)
    if appendix_match is None:
        raise SystemExit("Error: could not find docstart:nips_appendix in NIPS aux file.")
    page_values["manualDocPaperStartPage"] = docs_only_pages + 1
    page_values["manualDocPaperAppendixStartPage"] = docs_only_pages + int(appendix_match.group(1))

reader = PdfReader(str(pdf_path))
writer = PdfWriter()
writer.append(reader)

if len(writer.pages) < max(page_values.values()):
    raise SystemExit(
        f"Error: {pdf_path} has {len(writer.pages)} pages, "
        f"but index links target page {max(page_values.values())}"
    )

index_page_number = None
index_links = []
for page_number, page in enumerate(reader.pages):
    page_links = []
    for annotation_ref in page.get("/Annots") or []:
        annotation = annotation_ref.get_object()
        if annotation.get("/Subtype") == "/Link" and annotation.get("/Rect") is not None:
            page_links.append((annotation, [float(value) for value in annotation["/Rect"]]))
    if len(page_links) >= 2:
        index_page_number = page_number
        index_links = page_links
        break

if len(index_links) < 2:
    raise SystemExit(f"Error: could not infer index-row link rectangles in {pdf_path}")

index_links.sort(key=lambda item: item[1][1], reverse=True)
last_normal_link, last_rect = index_links[-1]
_, second_last_rect = index_links[-2]
row_delta = last_rect[1] - second_last_rect[1]
if row_delta >= 0:
    raise SystemExit(f"Error: invalid inferred index-row spacing in {pdf_path}")

paper_rect = [
    last_rect[0],
    last_rect[1] + row_delta,
    last_rect[2],
    last_rect[3] + row_delta,
]
appendix_rect = [
    paper_rect[0],
    paper_rect[1] + row_delta,
    paper_rect[2],
    paper_rect[3] + row_delta,
]

for rect, page_number in (
    (paper_rect, page_values["manualDocPaperStartPage"]),
    (appendix_rect, page_values["manualDocPaperAppendixStartPage"]),
):
    target_page = writer.pages[page_number - 1]
    target_top = float(target_page.mediabox.top)
    annotation = DictionaryObject(
        {
            NameObject("/Type"): NameObject("/Annot"),
            NameObject("/Subtype"): NameObject("/Link"),
            NameObject("/Rect"): ArrayObject([FloatObject(value) for value in rect]),
            NameObject("/Dest"): ArrayObject(
                [
                    target_page.indirect_reference,
                    NameObject("/XYZ"),
                    FloatObject(0),
                    FloatObject(target_top),
                    NullObject(),
                ]
            ),
        }
    )
    for visual_key in ("/Border", "/C", "/H"):
        if visual_key in last_normal_link:
            annotation[NameObject(visual_key)] = last_normal_link[visual_key]
    annotation[NameObject("/P")] = writer.pages[index_page_number].indirect_reference
    if writer.pages[index_page_number].annotations is None:
        writer.pages[index_page_number][NameObject("/Annots")] = ArrayObject()
    writer.pages[index_page_number].annotations.append(writer._add_object(annotation))

with NamedTemporaryFile(dir=pdf_path.parent, suffix=".pdf", delete=False) as temp_file:
    temp_path = Path(temp_file.name)
    writer.write(temp_file)

temp_path.replace(pdf_path)
PY
}

write_index_override_placeholders() {
  write_file_if_changed "${INDEX_OVERRIDES_FILE}" <<EOF
\providecommand{\manualDocPaperStartPage}{--}
\providecommand{\manualDocPaperAppendixStartPage}{--}
EOF
}

if [ "${BUILD_COMBINED}" = "true" ] || [ ! -f "${INDEX_OVERRIDES_FILE}" ]; then
  write_index_override_placeholders
fi

update_index_overrides() {
  python3 - <<'PY' "${COMBINED_DOCS_ONLY_FILE}" "${NIPS_MAIN_AUX}" "${INDEX_OVERRIDES_FILE}"
from pathlib import Path
import re
import sys

from pypdf import PdfReader

docs_only_pdf = Path(sys.argv[1])
nips_aux = Path(sys.argv[2])
output = Path(sys.argv[3])

docs_only_pages = len(PdfReader(str(docs_only_pdf)).pages)
aux_text = nips_aux.read_text()
appendix_match = re.search(r'\\newlabel\{docstart:nips_appendix\}\{\{[^}]*\}\{([^}]*)\}', aux_text)
if appendix_match is None:
    raise SystemExit("Error: could not find docstart:nips_appendix in NIPS aux file.")

paper_start_page = docs_only_pages + 1
paper_appendix_page = docs_only_pages + int(appendix_match.group(1))

text = (
    f"\\renewcommand{{\\manualDocPaperStartPage}}{{{paper_start_page}}}\n"
    f"\\renewcommand{{\\manualDocPaperAppendixStartPage}}{{{paper_appendix_page}}}\n"
)
if not output.exists() or output.read_text() != text:
    output.write_text(text)
PY
}

if [ "${SKIP_PAPER}" = "true" ]; then
  echo "Skipping NIPS manuscript build because --skip-paper was provided."
else
  build_nips_main
fi

for tex_name in "${indexed_tex_files[@]}"; do
  compile_tex_variants "${tex_name}"
done
if [ "${#unindexed_tex_files[@]}" -gt 0 ]; then
  for tex_name in "${unindexed_tex_files[@]}"; do
    compile_tex_variants "${tex_name}"
  done
fi
compile_tex_variants "${STANDALONE_APPENDIX_FILE}"
compile_tex_variants "documentation_index.tex"

if [ "${BUILD_COMBINED}" != "true" ]; then
  echo "Skipping combined manual PDFs. Pass --combine to rebuild merged outputs."
  finish
  exit 0
fi

generate_combined_include_file
echo "Compiling docs-only combined manual -> ${COMBINED_DOCS_ONLY_FILE}"
create_build_wrapper "docs_combined_compact.tex" combined_wrapper "" "false"
if [ "${FORCE_REBUILD}" = "true" ]; then
  cleanup_latexmk_target "docs_combined_compact"
fi
if ! (
  cd "${SCRIPT_DIR}"
  TEXINPUTS="${LATEX_TEXINPUTS}${TEXINPUTS:-}" \
    BIBINPUTS="${LATEX_BIBINPUTS}${BIBINPUTS:-}" \
    latexmk -pdf -interaction=nonstopmode -halt-on-error -file-line-error \
    -output-directory="${BUILD_DIR}" "${combined_wrapper}"
); then
  if [ -f "${BUILD_DIR}/docs_combined_compact.pdf" ]; then
    echo "Warning: latexmk returned nonzero for docs_combined_compact, but ${BUILD_DIR#${SCRIPT_DIR}/}/docs_combined_compact.pdf was produced." >&2
  else
    exit 1
  fi
fi
copy_rendered_pdf "docs_combined_compact" "${COMBINED_DOCS_ONLY_FILE}"

create_build_wrapper "docs_combined_compact.tex" combined_numbered_wrapper "${NUMBERED_SUFFIX}" "true"
echo "Compiling docs-only combined manual numbered variant -> ${COMBINED_NUMBERED_DOCS_ONLY_FILE}"
if [ "${FORCE_REBUILD}" = "true" ]; then
  cleanup_latexmk_target "docs_combined_compact${NUMBERED_SUFFIX}"
fi
if ! (
  cd "${SCRIPT_DIR}"
  TEXINPUTS="${LATEX_TEXINPUTS}${TEXINPUTS:-}" \
    BIBINPUTS="${LATEX_BIBINPUTS}${BIBINPUTS:-}" \
    latexmk -pdf -interaction=nonstopmode -halt-on-error -file-line-error \
    -output-directory="${BUILD_DIR}" "${combined_numbered_wrapper}"
); then
  if [ -f "${BUILD_DIR}/docs_combined_compact${NUMBERED_SUFFIX}.pdf" ]; then
    echo "Warning: latexmk returned nonzero for docs_combined_compact${NUMBERED_SUFFIX}, but ${BUILD_DIR#${SCRIPT_DIR}/}/docs_combined_compact${NUMBERED_SUFFIX}.pdf was produced." >&2
  else
    exit 1
  fi
fi
if [ ! -f "${BUILD_DIR}/docs_combined_compact${NUMBERED_SUFFIX}.pdf" ]; then
  echo "Error: expected rendered combined numbered PDF at ${BUILD_DIR}/docs_combined_compact${NUMBERED_SUFFIX}.pdf" >&2
  exit 1
fi
copy_rendered_pdf "docs_combined_compact${NUMBERED_SUFFIX}" "${COMBINED_NUMBERED_DOCS_ONLY_FILE}"

if [ "${SKIP_PAPER}" = "true" ]; then
  copy_pdf_if_needed "${COMBINED_DOCS_ONLY_FILE}" "${COMBINED_OUTPUT_FILE}"
  copy_pdf_if_needed "${COMBINED_NUMBERED_DOCS_ONLY_FILE}" "${COMBINED_NUMBERED_OUTPUT_FILE}"
  echo "Skipping paper merge and paper index links because --skip-paper was provided."
  copy_current_combined_pdf
  finish
  exit 0
fi

update_index_overrides
compile_tex_variants "documentation_index.tex"

echo "Recompiling docs-only combined manual with merged index page numbers -> ${COMBINED_DOCS_ONLY_FILE}"
if [ "${FORCE_REBUILD}" = "true" ]; then
  cleanup_latexmk_target "docs_combined_compact"
fi
if ! (
  cd "${SCRIPT_DIR}"
  TEXINPUTS="${LATEX_TEXINPUTS}${TEXINPUTS:-}" \
    BIBINPUTS="${LATEX_BIBINPUTS}${BIBINPUTS:-}" \
    latexmk -pdf -interaction=nonstopmode -halt-on-error -file-line-error \
    -output-directory="${BUILD_DIR}" "${combined_wrapper}"
); then
  if [ -f "${BUILD_DIR}/docs_combined_compact.pdf" ]; then
    echo "Warning: latexmk returned nonzero for docs_combined_compact, but ${BUILD_DIR#${SCRIPT_DIR}/}/docs_combined_compact.pdf was produced." >&2
  else
    exit 1
  fi
fi
copy_rendered_pdf "docs_combined_compact" "${COMBINED_DOCS_ONLY_FILE}"

echo "Recompiling docs-only combined manual numbered variant with merged index page numbers -> ${COMBINED_NUMBERED_DOCS_ONLY_FILE}"
if [ "${FORCE_REBUILD}" = "true" ]; then
  cleanup_latexmk_target "docs_combined_compact${NUMBERED_SUFFIX}"
fi
if ! (
  cd "${SCRIPT_DIR}"
  TEXINPUTS="${LATEX_TEXINPUTS}${TEXINPUTS:-}" \
    BIBINPUTS="${LATEX_BIBINPUTS}${BIBINPUTS:-}" \
    latexmk -pdf -interaction=nonstopmode -halt-on-error -file-line-error \
    -output-directory="${BUILD_DIR}" "${combined_numbered_wrapper}"
); then
  if [ -f "${BUILD_DIR}/docs_combined_compact${NUMBERED_SUFFIX}.pdf" ]; then
    echo "Warning: latexmk returned nonzero for docs_combined_compact${NUMBERED_SUFFIX}, but ${BUILD_DIR#${SCRIPT_DIR}/}/docs_combined_compact${NUMBERED_SUFFIX}.pdf was produced." >&2
  else
    exit 1
  fi
fi
copy_rendered_pdf "docs_combined_compact${NUMBERED_SUFFIX}" "${COMBINED_NUMBERED_DOCS_ONLY_FILE}"

merge_pdfs "${COMBINED_OUTPUT_FILE}" "${COMBINED_DOCS_ONLY_FILE}" "${NIPS_MAIN_PDF}"
merge_pdfs "${COMBINED_NUMBERED_OUTPUT_FILE}" "${COMBINED_NUMBERED_DOCS_ONLY_FILE}" "${NIPS_MAIN_PDF}"
add_combined_index_paper_links "${COMBINED_OUTPUT_FILE}"
add_combined_index_paper_links "${COMBINED_NUMBERED_OUTPUT_FILE}"
copy_current_combined_pdf
finish
