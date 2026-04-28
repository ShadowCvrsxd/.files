#!/bin/bash

# === Пути ===
STATIC_DIR="$HOME/my/wallpapers"
LIVE_DIR="$HOME/my/wallpapers/live"
CACHE_DIR="$HOME/.cache/wall-thumbs"
STATE_FILE="$HOME/.cache/last-wallpaper"
PYWAL_SCRIPT="$HOME/.config/hypr/scripts/pywal-to-hypr.sh"
ASCII_DIR="$HOME/.config/fastfetch/logos"
ASCII_TMP="/tmp/current_ascii_path.txt"

mkdir -p "$CACHE_DIR"

# === Определяем активный монитор ===
MONITOR=$(hyprctl monitors -j | jq -r '.[0].name')
[ -z "$MONITOR" ] && MONITOR="eDP-1"

# === Выбор типа обоев ===
TYPE=$(echo -e "🖼 Статичные обои\n🎞 Живые обои" | rofi -dmenu -theme ~/.config/rofi/fullscreen-theme-wallpaper.rasi -p "Тип:")
[ -z "$TYPE" ] && exit

if [[ "$TYPE" == *"Живые"* ]]; then
    WALLPAPER_DIR="$LIVE_DIR"
    IS_LIVE=true
else
    WALLPAPER_DIR="$STATIC_DIR"
    IS_LIVE=false
fi

# === Асинхронная генерация миниатюр ===
(
  find "$WALLPAPER_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mov" \) | while read -r WALL; do
      NAME=$(basename "$WALL")
      THUMB="$CACHE_DIR/${NAME%.*}.png"

      if [ ! -f "$THUMB" ] || [ "$WALL" -nt "$THUMB" ]; then
          if [[ "$WALL" =~ \.mp4$|\.webm$|\.mov$ ]]; then
              ffmpeg -ss 3 -y -i "$WALL" -vframes 1 -vf "scale=260:260:force_original_aspect_ratio=decrease" "$THUMB" -loglevel quiet
          else
              ffmpeg -y -i "$WALL" -vf "scale=260:260:force_original_aspect_ratio=decrease" "$THUMB" -loglevel quiet
          fi
      fi
  done
) & disown

sleep 0.2

# === Генерация списка для Rofi ===
LIST=""
while IFS= read -r WALL; do
    NAME=$(basename "$WALL")
    THUMB="$CACHE_DIR/${NAME%.*}.png"
    LIST+="$NAME\x00icon\x1f$THUMB\n"
done < <(find "$WALLPAPER_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mov" \) | sort)

SELECTED=$(echo -e "$LIST" | rofi -dmenu -show-icons -theme ~/.config/rofi/fullscreen-theme-wallpaper.rasi -p "Выбери обои:")
[ -z "$SELECTED" ] && exit

FILE=$(find "$WALLPAPER_DIR" -type f -name "$SELECTED" | head -n 1)

# === Проверка awww (заменил swww-daemon на awww-daemon) ===
if ! pgrep -x "awww-daemon" >/dev/null; then
    awww-daemon &
    sleep 1
fi

#apply pywal
apply_pywal() {
    local TARGET="$1"
    wal -i "$TARGET" -n &>/dev/null
    update_ascii_path
    [ -x "$PYWAL_SCRIPT" ] && bash "$PYWAL_SCRIPT"
    reload_kitty_all
}

# === Обновление ASCII ===
update_ascii_path() {
    local BASENAME=$(basename "$FILE" | tr '[:upper:]' '[:lower:]')
    local KEY=$(echo "$BASENAME" | cut -d. -f1 | cut -d'-' -f1)
    local MATCH=$(find "$ASCII_DIR" -type f -iname "${KEY}.txt" | head -n 1)

    if [ -n "$MATCH" ]; then
        echo "$MATCH" > "$ASCII_TMP"
    elif [ ! -s "$ASCII_TMP" ]; then
        echo "$ASCII_DIR/herta.txt" > "$ASCII_TMP"
    fi

    if command -v fish >/dev/null 2>&1; then
        fish -c "set -Ux ASCII_PATH (cat $ASCII_TMP)"
    fi
}

# === Kitty обновление ===
reload_kitty_all() {
    if command -v kitty >/dev/null; then
        for sock in /tmp/kitty*/kitty.sock; do
            kitty @ --to unix:$sock set-colors --all --configured ~/.cache/wal/colors-kitty.conf 2>/dev/null
        done
    fi
}

# === walogram ===
apply_walogram_theme() {
  # Берем путь из аргумента, если он пуст — используем глобальную FILE
  local SRC="${1:-$FILE}"
  local TMP_DIR="$HOME/.cache/walogram"
  local TMP_BG="$TMP_DIR/walogram_bg.png"

  if ! command -v walogram >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$TMP_DIR"

  if [[ "$SRC" =~ \.(mp4|webm|mov)$ ]]; then
    # Твоя рабочая строка для видео
    ffmpeg -y -ss 3 -i "$SRC" -vframes 1 -vf "scale=1920:-2:flags=lanczos,format=rgba" "$TMP_BG" -loglevel error
  else
    if command -v magick >/dev/null 2>&1; then
      # Твоя рабочая строка для фото через magick
      magick convert "$SRC" -auto-orient -resize "1920x1080>" -strip "$TMP_BG"
    else
      # Твоя рабочая строка для фото через ffmpeg
      ffmpeg -y -i "$SRC" -vf "scale='if(gt(iw,1920),1920,iw)':'-2':flags=lanczos,format=rgba" "$TMP_BG" -loglevel error
    fi
  fi

  # Важно: всегда скармливаем именно созданный TMP_BG
  walogram -i "$TMP_BG" >/dev/null 2>&1 || walogram >/dev/null 2>&1
}

# === Основная логика ===
if [ "$IS_LIVE" = false ]; then
    # Убиваем живые обои, если они были
    pkill -9 mpvpaper 2>/dev/null
    
    # Ставим картинку через awww
    awww img "$FILE" --transition-type wave --transition-fps 60 --transition-duration 1.2
    echo "$FILE" > "$STATE_FILE"

    # Обновляем Carettab
    CARETTAB_JUNIPER="$HOME/my/misc/carettab/img/juniper.jpg"
    if [ -f "$CARETTAB_JUNIPER" ]; then
        cp "$FILE" "$CARETTAB_JUNIPER"
    fi

    apply_pywal "$FILE"
    apply_walogram_theme "$FILE"

else
    # Живые обои
    pkill mpvpaper 2>/dev/null
    sleep 0.1 # Даем время порту освободиться, если нужно
    
    mpvpaper -s -o "no-audio loop --vo=gpu --hwdec=auto --panscan=1.0" "$MONITOR" "$FILE" &
    echo "$FILE" > "$STATE_FILE"

    apply_pywal "$FILE"
    apply_walogram_theme "$FILE"
fi