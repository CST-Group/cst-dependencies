#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:-./jars}"
TARGET_DIR="${TARGET_DIR:-./maven-repo}"

DEFAULT_GROUP_ID="${DEFAULT_GROUP_ID:-com.cst-dependencies}"
DEFAULT_VERSION="${DEFAULT_VERSION:-1.0.0}"

# --- Funções Auxiliares ---

# Verifica se os comandos necessários existem
require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Erro Crítico: O comando '$1' não foi encontrado. Por favor, instale-o."; exit 1; }
}

# Gera o arquivo maven-metadata.xml para um artefato
gen_metadata() {
  local groupPath="$1" artifactId="$2"
  local artifactDir="$TARGET_DIR/$groupPath/$artifactId"
  [ -d "$artifactDir" ] || return 0

  # Usa 'mapfile', que é a forma correta e segura para o seu Bash 5.2
  local versions=()
  mapfile -t versions < <(find "$artifactDir" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" | sort -V)

  [ "${#versions[@]}" -gt 0 ] || return 0

  local latest="${versions[-1]}"
  local meta="$artifactDir/maven-metadata.xml"
  local ts
  ts=$(date -u +"%Y%m%d%H%M%S")

  # Gera o conteúdo do XML
  {
    echo '<metadata>'
    echo "  <groupId>$(echo "$groupPath" | tr '/' '.')</groupId>"
    echo "  <artifactId>$artifactId</artifactId>"
    echo '  <versioning>'
    echo "    <latest>$latest</latest>"
    echo "    <release>$latest</release>"
    echo '    <versions>'
    for v in "${versions[@]}"; do echo "      <version>$v</version>"; done
    echo '    </versions>'
    echo "    <lastUpdated>$ts</lastUpdated>"
    echo '  </versioning>'
    echo '</metadata>'
  } > "$meta"
  echo "    -> Metadados atualizados para $artifactId"
}

# --- Função Principal de Processamento ---

process_jar() {
  local jar="$1"
  local filename base artifactId version groupId classifier="" groupPath artifactPath

  filename="$(basename -- "$jar")"
  base="${filename%.jar}"

  echo "-----------------------------------------"
  echo "Processando: $filename"

  local tmp
  tmp="$(mktemp)"

  # Tenta ler pom.properties do JAR (agora mostrando erros do unzip)
  if unzip -p "$jar" "META-INF/maven/*/*/pom.properties" > "$tmp"; then
    echo "  -> Encontrado pom.properties."
    groupId="$(sed -n 's/^groupId=\(.*\)/\1/p' "$tmp" | head -n1)"
    artifactId="$(sed -n 's/^artifactId=\(.*\)/\1/p' "$tmp" | head -n1)"
    version="$(sed -n 's/^version=\(.*\)/\1/p' "$tmp" | head -n1)"
  else
    echo "  -> pom.properties não encontrado. Deduzindo pelo nome do arquivo."
    artifactId="${base%*-*}"
    version="${base##*-}"
    if [ "$artifactId" = "$base" ]; then
      artifactId="$base"
      version="$DEFAULT_VERSION"
    fi
    groupId="$DEFAULT_GROUP_ID"
  fi
  rm -f "$tmp"

  # Tenta detectar um classificador (ex: -sources, -javadoc)
  if [[ "$base" =~ ^${artifactId//./\\.}-${version//./\\.}-(.+)$ ]]; then
    classifier="-${BASH_REMATCH[1]}"
  fi

  groupPath="$(echo "$groupId" | tr '.' '/')"
  artifactPath="$TARGET_DIR/$groupPath/$artifactId/$version"

  echo "  -> Coordenadas: $groupId:$artifactId:$version"
  mkdir -p "$artifactPath"

  # Copia o JAR e gera o POM
  cp "$jar" "$artifactPath/$artifactId-$version${classifier}.jar"

  cat > "$artifactPath/$artifactId-$version.pom" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>$groupId</groupId>
  <artifactId>$artifactId</artifactId>
  <version>$version</version>
  <packaging>jar</packaging>
</project>
EOF

  echo "  -> Arquivos .jar e .pom criados em '$artifactPath'."
  gen_metadata "$groupPath" "$artifactId"
}

# --- Execução Principal ---
require unzip
require sed
require sort

# Limpa o diretório de destino para um começo limpo
if [ -d "$TARGET_DIR" ]; then
    echo "Limpando diretório de destino: $TARGET_DIR"
    rm -rf "$TARGET_DIR"/*
fi
mkdir -p "$TARGET_DIR"

shopt -s nullglob
count=0
echo "Iniciando processamento de JARs em '$SOURCE_DIR'..."

for jar in "$SOURCE_DIR"/*.jar; do
  process_jar "$jar"
  ((count++))
done

shopt -u nullglob

if [ "$count" -eq 0 ]; then
  echo "Nenhum arquivo .jar encontrado em '$SOURCE_DIR'."
  exit 1
fi

echo "========================================="
echo "✅ SUCESSO! $count JARs processados."
echo "✅ Repositório Maven gerado em: $TARGET_DIR"
