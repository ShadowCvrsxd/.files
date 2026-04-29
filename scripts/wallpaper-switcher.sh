#!/bin/bash

# === Пути ===
STATIC_DIR="$HOME/my/wallpapers"
LIVE_DIR="$HOME/my/wallpapers/live"
CACHE_DIR="$HOME/.cache/wall-thumbs"
STATE_FILE="$HOME/.cache/last-wallpaper"
PYWAL_SCRIPT="$HOME/.config/hypr/scripts/pywal-to-hypr.sh"
ASCII_DIR="$HOME/.config/fastfetch/logos"
ASCII_TMP="/tmp/current_ascii_path.txt"
ICON_DIR="$HOME/.local/share/icons"
WALLPAPER_DIR="$STATIC_DIR"

mkdir -p "$CACHE_DIR"

# === Настройки сетки ===
columns=7  # Количество колонок

# === Определяем активный монитор ===
MONITOR=$(hyprctl monitors -j | jq -r '.[0].name')
[ -z "$MONITOR" ] && MONITOR="eDP-1"

# === Асинхронная генерация миниатюр (для Rofi) ===
(
  find "$STATIC_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mov" \) | while read -r WALL; do
      NAME=$(basename "$WALL")
      THUMB="$CACHE_DIR/${NAME%.*}.png"

      if [ ! -f "$THUMB" ] || [ "$WALL" -nt "$THUMB" ]; then
          if [[ "$WALL" =~ \.(mp4|webm|mov)$ ]]; then
              ffmpeg -ss 3 -y -i "$WALL" -vframes 1 -vf "scale=260:260:force_original_aspect_ratio=decrease" "$THUMB" -loglevel quiet
          else
              ffmpeg -y -i "$WALL" -vf "scale=260:260:force_original_aspect_ratio=decrease" "$THUMB" -loglevel quiet
          fi
      fi
  done
) & disown

# === 1. Выбор категории ===
mapfile -t CAT_ARRAY < <(find "$WALLPAPER_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)
num_cats=$(( ${#CAT_ARRAY[@]} + 1 )) 
cat_lines=$(( (num_cats + columns - 1) / columns ))

CAT_LIST="All Wallpapers\x00icon\x1fview-list-symbolic"
for cat_name in "${CAT_ARRAY[@]}"; do
    CAT_ICON=$(find "$ICON_DIR" "$ASCII_DIR" -maxdepth 1 -type f \( -iname "${cat_name}.png" -o -iname "${cat_name}.svg" \) | head -n 1)
    [[ -n "$CAT_LIST" ]] && CAT_LIST+="\n"
    if [[ -n "$CAT_ICON" ]]; then
        CAT_LIST+="${cat_name}\x00icon\x1f${CAT_ICON}"
    else
        CAT_LIST+="${cat_name}\x00icon\x1ffolder-nordic"
    fi
done

SEL_CAT=$(echo -e "$CAT_LIST" | rofi -dmenu -show-icons \
    -theme ~/.config/rofi/fullscreen-theme-wallpaper.rasi \
    -theme-str "listview { columns: $columns; lines: $cat_lines; }" \
    -p "Категория:")
[ -z "$SEL_CAT" ] && exit

if [[ "$SEL_CAT" == "All Wallpapers" ]]; then
    FINAL_DIR="$WALLPAPER_DIR"
else
    FINAL_DIR="$WALLPAPER_DIR/$SEL_CAT"
fi

# === 2. Выбор конкретных обоев ===
mapfile -t WALL_FILES < <(find "$FINAL_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mov" \) -printf "%f\n" | sort)
num_walls=${#WALL_FILES[@]}
wall_lines=$(( (num_walls + columns - 1) / columns ))
[[ $wall_lines -gt 3 ]] && wall_lines=3

LIST=""
for file in "${WALL_FILES[@]}"; do
    [[ -n "$LIST" ]] && LIST+="\n"
    LIST+="${file}\x00icon\x1f$CACHE_DIR/${file%.*}.png"
done

SELECTED=$(echo -e "$LIST" | rofi -dmenu -show-icons \
    -theme ~/.config/rofi/fullscreen-theme-wallpaper.rasi \
    -theme-str "listview { columns: $columns; lines: $wall_lines; }" \
    -p "Выбери ($SEL_CAT):")
[ -z "$SELECTED" ] && exit

FILE=$(find "$FINAL_DIR" -type f -name "$SELECTED" | head -n 1)

# === Функции обновления ===
update_ascii_path() {
    local BASENAME=$(basename "$FILE" | tr '[:upper:]' '[:lower:]')
    local KEY=$(echo "$BASENAME" | cut -d. -f1 | cut -d'-' -f1)
    local MATCH=$(find "$ASCII_DIR" -type f -iname "${KEY}.txt" | head -n 1)
    [ -z "$MATCH" ] && MATCH="$ASCII_DIR/herta.txt"
    echo "$MATCH" > "$ASCII_TMP"
    [ -n "$(command -v fish)" ] && fish -c "set -Ux ASCII_PATH (cat $ASCII_TMP)"
}

reload_kitty_all() {
    [ -n "$(command -v kitty)" ] && for sock in /tmp/kitty*/kitty.sock; do
        kitty @ --to unix:$sock set-colors --all --configured ~/.cache/wal/colors-kitty.conf 2>/dev/null
    done
}

apply_pywal() {
    wal -i "$1" -n &>/dev/null
    update_ascii_path
    [ -x "$PYWAL_SCRIPT" ] && bash "$PYWAL_SCRIPT"
    reload_kitty_all
}

# === walogram (Твой оригинальный синтаксис) ===
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

# === Основная логика применения ===
pkill -9 mpvpaper 2>/dev/null

NAME=$(basename "$FILE")
IMG_FOR_EXTERNAL="$CACHE_DIR/${NAME%.*}_full.png"

if [[ "$FILE" =~ \.(mp4|webm|mov)$ ]]; then
    # Живые обои
    mpvpaper -s -o "no-audio loop --vo=gpu --hwdec=auto --panscan=1.0" "$MONITOR" "$FILE" &
    
    # Создаем качественный Full HD кадр
    if [ ! -f "$IMG_FOR_EXTERNAL" ]; then
        ffmpeg -y -ss 3 -i "$FILE" -vframes 1 -vf "scale=1920:-1" "$IMG_FOR_EXTERNAL" -loglevel quiet
    fi
else
    # Статичные обои
    if ! pgrep -x "awww-daemon" >/dev/null; then
        awww-daemon &
        sleep 0.5
    fi
    awww img "$FILE" --transition-type wave --transition-fps 60 --transition-duration 1.2
    IMG_FOR_EXTERNAL="$FILE"
fi

# Сохраняем состояние
echo "$FILE" > "$STATE_FILE"

# Обновление Carettab
CARETTAB_JUNIPER="$HOME/my/misc/carettab/img/juniper.jpg"
[ -f "$CARETTAB_JUNIPER" ] && cp "$IMG_FOR_EXTERNAL" "$CARETTAB_JUNIPER"

# Применяем темы
apply_pywal "$IMG_FOR_EXTERNAL"
# ПЕРЕДАЕМ ИМЕННО IMG_FOR_EXTERNAL, чтобы walogram не пытался резать видео заново
apply_walogram_theme "$IMG_FOR_EXTERNAL"