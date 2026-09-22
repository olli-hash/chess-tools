LINE_ROOT="$HOME/schachdb"

mark_prefix=$'\e[1;48;5;208m'
mark_suffix=$'\e[0m'

bold_prefix=$'\e[1m'
bold_suffix=$'\e[0m'

help() {
    cat <<EOF
SchachDB Line Navigation Funktionen:
${bold_prefix}set-line-focus${bold_suffix}  Line auswählen und Einstiegspunkt festlegen.
${bold_prefix}line-view${bold_suffix}       Aktuelle Line vollständig anzeigen.
${bold_prefix}n${bold_suffix}               Einen Halbzug vorwärts gehen.
${bold_prefix}p${bold_suffix}               Einen Halbzug zurückgehen.
${bold_prefix}comment${bold_suffix}         "comment" an der aktuellen Position öffnen/erzeugen.
${bold_prefix}reflect${bold_suffix}         "reflection_next_move" an der aktuellen Position öffnen/erzeugen.
${bold_prefix}help${bold_suffix}            Diese Hilfe anzeigen.
Reset: exec bash
EOF
}


set-line-focus() {
    local -a lines=()
    local file line
    local choice
    local entry

    # stop- und linestop-Marker suchen
    while IFS= read -r -d '' file; do
        line="${file#"$LINE_ROOT"/}"
        line="${line%/*}"
        lines+=("$line")
    done < <(
        find "$LINE_ROOT" -type f \( -name stop -o -name linestop \) -print0
    )

    if ((${#lines[@]} == 0)); then
        echo "Keine Lines gefunden."
        return 1
    fi

    echo "Verfügbare Lines:"
    for ((i = 0; i < ${#lines[@]}; i++)); do
        printf '%d) %s\n' "$((i + 1))" "${lines[i]//\// }"
    done

    while true; do
        read -r -p "Line auswählen: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] &&
           ((choice >= 1 && choice <= ${#lines[@]})); then
            break
        fi

        echo "Ungültige Auswahl."
    done

    IFS='/' read -r -a line_focus <<< "${lines[choice - 1]}"

    while true; do
        read -r -p "Einstiegspunkt [Anfang/Ende/Zugnummer, Standard: Anfang]: " entry

        [[ -z "$entry" ]] && entry="0"

        if [[ "$entry" == "Anfang" || "$entry" == "anfang" ]]; then
            line_focus_index=0
            break
        fi

        if [[ "$entry" == "Ende" || "$entry" == "ende" ]]; then
            line_focus_index=${#line_focus[@]}
            break
        fi

        if [[ "$entry" =~ ^[0-9]+$ ]] &&
           ((entry >= 0 && entry <= ${#line_focus[@]})); then
            line_focus_index=$entry
            break
        fi

        echo "Ungültiger Einstiegspunkt."
    done
    
    local path
    path="$(_line_focus_path)"

    cd "$path" || return 1
    touch .

    line-view
     
     
    echo "
Für Hilfe 'help' eingeben."
}

line-view() {
    local output=""
    local move_number
    local i
    local move

    if ((${#line_focus[@]} == 0)); then
        echo "Keine Line ausgewählt."
        return 1
    fi

    if ((line_focus_index == 0)); then
        #output=$'\e[1mstart\e[0m '
        output="${mark_prefix}start${mark_suffix}"
    fi

    for ((i = 0; i < ${#line_focus[@]}; i++)); do
        move="${line_focus[i]}"
        move_number=$((i / 2 + 1))

        if ((i % 2 == 0)); then
            output+="$move_number. "
        fi

        if ((i + 1 == line_focus_index)); then
            #output+=$'\e[1m'"$move"$'\e[0m'
            output+="${mark_prefix} ${move} ${mark_suffix}"
        else
            output+="$move"
        fi

        if ((i + 1 < ${#line_focus[@]})); then
            output+=" "
        fi
    done

    printf '%s\n' "$output"
}


_line_focus_path() {
    local path="$LINE_ROOT"
    local i

    for ((i = 0; i < line_focus_index; i++)); do
        path+="/${line_focus[i]}"
    done

    printf '%s\n' "$path"
}


_goto_line_focus() {
    local path
    path="$(_line_focus_path)"

    cd "$path" || return 1
    touch .
}


_n() {
    if ((line_focus_index < ${#line_focus[@]})); then
        ((line_focus_index++))
    fi

    _goto_line_focus
}


_p() {
    if ((line_focus_index > 0)); then
        ((line_focus_index--))
    fi

    _goto_line_focus
}


_move_target() {
    local move="$1"

    # Rochaden ignorieren
    [[ "$move" == O-O || "$move" == O-O-O ]] && return 1

    # Letzte Feldkoordinate der SAN-Notation ermitteln
    if [[ "$move" =~ ([a-h][1-8]) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}


_n_search() {
    local type="$1"
    local value="$2"
    local i target

    for ((i = line_focus_index + 1; i <= ${#line_focus[@]}; i++)); do
        target="$(_move_target "${line_focus[i-1]}")" || continue

        case "$type" in
            square)
                [[ "$target" == "$value" ]] || continue
                ;;
            rank)
                [[ "${target:1:1}" == "$value" ]] || continue
                ;;
            file)
                [[ "${target:0:1}" == "$value" ]] || continue
                ;;
        esac

        line_focus_index=$i
        _goto_line_focus
        return
    done

    echo "Kein passender Zug vorwärts gefunden: $2"
    return 1
}


_p_search() {
    local type="$1"
    local value="$2"
    local i target

    for ((i = line_focus_index - 1; i >= 1; i--)); do
        target="$(_move_target "${line_focus[i-1]}")" || continue

        case "$type" in
            square)
                [[ "$target" == "$value" ]] || continue
                ;;
            rank)
                [[ "${target:1:1}" == "$value" ]] || continue
                ;;
            file)
                [[ "${target:0:1}" == "$value" ]] || continue
                ;;
        esac

        line_focus_index=$i
        _goto_line_focus
        return
    done

    echo "Kein passender Zug rückwärts gefunden: $2"
    return 1
}


n() {
    if (($# == 0)); then
        _n
        return
    fi

    if (($# != 1)); then
        echo "Verwendung: n [Anzahl|Zielfeld|Reihe|Linie]"
        return 1
    fi

    local arg="$1"

    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        ((line_focus_index += arg))

        if ((line_focus_index > ${#line_focus[@]})); then
            line_focus_index=${#line_focus[@]}
        fi

        _goto_line_focus

    elif [[ "$arg" =~ ^[a-h][1-8]$ ]]; then
        _n_search square "$arg"

    elif [[ "$arg" =~ ^_[1-8]$ ]]; then
        _n_search rank "${arg:1}"

    elif [[ "$arg" =~ ^[a-h]_$ ]]; then
        _n_search file "${arg:0:1}"

    else
        echo "Ungültiger Parameter: $arg"
        return 1
    fi
}


p() {
    if (($# == 0)); then
        _p
        return
    fi

    if (($# != 1)); then
        echo "Verwendung: p [Anzahl|Zielfeld|Reihe|Linie]"
        return 1
    fi

    local arg="$1"

    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        ((line_focus_index -= arg))

        if ((line_focus_index < 0)); then
            line_focus_index=0
        fi

        _goto_line_focus

    elif [[ "$arg" =~ ^[a-h][1-8]$ ]]; then
        _p_search square "$arg"

    elif [[ "$arg" =~ ^_[1-8]$ ]]; then
        _p_search rank "${arg:1}"

    elif [[ "$arg" =~ ^[a-h]_$ ]]; then
        _p_search file "${arg:0:1}"

    else
        echo "Ungültiger Parameter: $arg"
        return 1
    fi
}






comment() {
    local path
    path="$(_line_focus_path)/comment"

    touch "$path"    
    { xdg-open "$path" >/dev/null 2>&1 & disown; } 2>/dev/null
}


reflect() {
    local path
    path="$(_line_focus_path)/reflection_next_move"

    touch "$path"
    { xdg-open "$path" >/dev/null 2>&1 & disown; } 2>/dev/null
}










set-line-focus


