#!/opt/homebrew/bin/bash
#!/usr/bin/env bash
GREEN='\033[0;32m'
RED='\033[0;31m'
LGREEN='\033[1;32m'
LRED='\033[1;31m'
VIOLET='\033[0;35m'
WHITE='\033[0m'
CURSORUP='\033[1A'
ERASEUNTILLENDOFLINE='\033[K'

#set -euo pipefail
#IFS=$'\n\t'

# little helpers for terminal print control and key input
ESC=$(printf "\033")
cursor_blink_on() { printf "$ESC[?25h"; }
cursor_blink_off() { printf "$ESC[?25l"; }
cursor_to() { printf "$ESC[$1;${2:-1}H"; }
print_option() { printf "$1 "; }
print_selected_on() { printf "$ESC[7m"; }
print_selected_off() { printf "$ESC[27m"; }
get_cursor_row() {
  IFS=';' read -sdR -p $'\E[6n' ROW COL
  echo ${ROW#*[}
}
get_cursor_column() {
  IFS=';' read -sdR -p $'\E[6n' ROW COL
  echo ${COL}
}
repl() { printf '%.0s'"$1" $(seq 1 "$2"); }
key_input() {
  local key=""
  local extra=""
  local escKey=$(echo -en "\033")
  local upKey=$(echo -en "\033[A")
  local downKey=$(echo -en "\033[B")

  read -s -n1 key 2>/dev/null >&2
  while read -s -n1 -t .0001 extra 2>/dev/null >&2; do
    key="$key$extra"
  done

  if [[ $key = $upKey ]]; then
    echo "up"
  elif [[ $key = $downKey ]]; then
    echo "down"
  elif [[ $key = $escKey ]]; then
    echo "esc"
  elif [[ $key = "" ]]; then
    echo "enter"
  fi
}

function refresh_window {
  # формат вызова
  # refresh_window y x height width shift "@"

  local MaxWindowWidth
  local left_x
  local top_y
  local ReturnKey=""
  local temp
  local -a ms
  local -a menu_items
  local height
  local i=0
  local shift_y
  ms=("$@")
  left_x=${ms[1]}
  top_y=${ms[0]}
  MaxWindowWidth=${ms[3]}
  menu_items=("${ms[@]:5}")
  height=${ms[2]}
  shift_y=${ms[4]}

  cursor_to $(($top_y)) $(($left_x))
  printf "┌"
  repl "─" $(($MaxWindowWidth + 3))
  printf "┐"

  for ((i = 0; i < ${height}; i++)); do
    cursor_to $(($top_y + ${i} + 1)) $(($left_x))
    print_option "│  ${menu_items[${i} + ${shift_y}]}"
    repl " " $((${MaxWindowWidth} - ${#menu_items[${i} + ${shift_y}]}))
    printf "│"
  done

  cursor_to $(($top_y + ${i} + 1)) $(($left_x))
  printf "└"
  repl "─" $(($MaxWindowWidth + 3))
  printf "┘"
}

function vertical_menu {
  # формат вызова
  # vertical_menu y x height width "@"
  # если x = center - то центрирование по горизонтали
  # если y = 	center - то центрирование по вертикали
  # 		 =	current - выводим меню в текущей строке
  # если height = 0 - не устанавливать высоты (она будет посчитана автоматически)
  #			  = число - установить высоту окна равную числу. Пункты меню будут скролироваться
  #	width = число. Если строка будет больше этого числа - то ширина будет расширена до него
  # если среди пунктов меню встречается слово default со знаком =, то это значит установка пункта меню по умолчанию
  # этот пункт меню будет выбранным при выводе меню
  # vertical_menu y x height width  "default=2" "First Item" "Second Item" "Third Item"
  local MaxWindowWidth
  local left_x
  local top_y
  local ReturnKey=""
  local -a ms
  local -a menu_items
  local size
  local lines
  local columns
  local current_y
  local skip_lines=0
  local height
  local shift_y=0
  size=$(stty size)
  lines=${size% *}
  columns=${size#* }

  # Обработка и удаление аргумента default, если он присутствует
  local default_selected_index=0
  local new_menu_items=()
  for arg in "$@"; do
    if [[ $arg == default=* ]]; then
      default_selected_index=${arg#default=}
    else
      new_menu_items+=("$arg")
    fi
  done

  ms=("${new_menu_items[@]:0:4}")
  menu_items=("${new_menu_items[@]:4}")
  left_x=${ms[1]}
  top_y=${ms[0]}
  MaxWindowWidth=${ms[3]}
  current_y=$(get_cursor_row)

  if ((${ms[2]} == 0)); then
    height=${#menu_items[@]}
  else
    # если требуемая высота больше чем количество пунктов меню, уменьшаем ее
    if ((${ms[2]} > ${#menu_items[@]})); then
      height=${#menu_items[@]}
    else
      height=${ms[2]}
    fi
  fi

  #find the width of the window
  for el in "${menu_items[@]}"; do
    if ((${MaxWindowWidth} < ${#el})); then
      MaxWindowWidth=${#el}
    fi
  done
  ((MaxWindowWidth = ${MaxWindowWidth} + 2))

  if [[ ${ms[1]} == "center" ]]; then
    ((left_x = (${columns} - ${MaxWindowWidth} - 6) / 2))
  fi
  if [[ ${ms[0]} == "center" ]]; then
    ((top_y = (${lines} - ${height} - 2) / 2))
  fi

  if [[ ${ms[0]} == "current" ]]; then
    # если меню не поместится - надо сдвинуть экран
    ((skip_lines = 0))
    if (((${current_y} + ${height} + 1) > ${lines})); then
      ((skip_lines = ${current_y} + ${height} - ${lines} + 2))
      echo -en ${ESC}"[${skip_lines}S"
    fi
    ((top_y = ${current_y} - ${skip_lines}))
    ((current_y = top_y))
  fi
  refresh_window ${top_y} ${left_x} ${height} ${MaxWindowWidth} ${shift_y} "${menu_items[@]}"

  # ensure cursor and input echoing back on upon a ctrl+c during read -s
  trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
  cursor_blink_off

  local selected=${default_selected_index}
  local previous_selected=${default_selected_index}
  while true; do
    # print options by overwriting the last lines

    cursor_to $(($top_y + $previous_selected + 1)) $(($left_x))
    print_option "│  ${menu_items[$previous_selected + ${shift_y}]}"
    repl " " $(($MaxWindowWidth - ${#menu_items[$previous_selected + ${shift_y}]}))
    printf "│"

    cursor_to $(($top_y + $selected + 1)) $(($left_x))
    printf "│ "
    print_selected_on
    printf " ${menu_items[${selected} + ${shift_y}]}"
    repl " " $(($MaxWindowWidth - ${#menu_items[$selected + ${shift_y}]}))
    print_selected_off
    printf " │"

    # user key control
    ReturnKey=$(key_input)
    case ${ReturnKey} in
    enter) break ;;
    esc)
      selected=255
      break
      ;;
    up)
      previous_selected=${selected}
      ((selected--))
      if [[ ${selected} -lt 0 ]]; then
        if ((${shift_y} > 0)); then
          ((shift_y--))
          refresh_window ${top_y} ${left_x} ${height} ${MaxWindowWidth} ${shift_y} "${menu_items[@]}"
        fi
        selected=0
      fi
      ;;
    down)
      previous_selected=${selected}
      ((selected++))
      if [[ ${selected} -ge ${height} ]]; then
        if (((${shift_y} + ${selected}) < ${#menu_items[@]})); then
          ((shift_y++))
          refresh_window ${top_y} ${left_x} ${height} ${MaxWindowWidth} ${shift_y} "${menu_items[@]}"
        fi
        selected=${previous_selected}
      fi
      ;;
    esac
  done

  printf "\n"
  cursor_blink_on
  cursor_to ${current_y} 1
  if [[ ${ms[0]} == "current" ]]; then
    # очистить выведенное меню
    echo -en ${ESC}"[0J"
  fi
  ((selected += ${shift_y}))
  return ${selected}
}

function fn_bui_setup_get_env() {
  # save the home dir
  local _script_name=${BASH_SOURCE[0]}
  local _script_dir=${_script_name%/*}

  if [[ "$_script_name" == "$_script_dir" ]]; then
    # _script name has no path
    _script_dir="."
  fi

  # convert to absolute path
  _script_dir=$(
    cd $_script_dir
    pwd -P
  )

  export BUI_HOME=$_script_dir
}

clear
AddServer() {
  clear
  local regex="^[a-zA-Z0-9]+([-\.][a-zA-Z0-9]+)*(\.[a-zA-Z]{2,})?$|^[a-zA-Z0-9]+$"
  server_name=
  while true; do
    # Запрос IP-адреса у пользователя
    read -p "Введите IP-адрес нового сервера или нажмите Enter для выхода: " ip_address

    # Проверка на пустой ввод - выход из скрипта
    if [[ -z "$ip_address" ]]; then
      echo -e -n ${WHITE}${CURSORUP}${ERASEUNTILLENDOFLINE}
      return
    fi

    # Проверка IP-адреса на доступность с помощью пинга
    if ping -c 1 -W 2 "$ip_address" &>/dev/null; then
      echo -e "IP-адрес ${GREEN}$ip_address${WHITE} доступен."
      break
    else
      echo -e "IP-адрес ${RED}$ip_address${WHITE} недоступен. Попробуйте ввести другой адрес."
    fi
  done
  echo "Теперь нужно выбрать имя сервера."
  echo "Имя сервера имеет смысл только для вас и содержит латинские символы и цифры."
  echo "Имя можно выбрать по своему усмотрению."
  echo
  echo -e -n "${WHITE}Введите имя сервера (Enter для выхода):${GREEN}"
  read -e -p " " server_name
  while true; do
    if [[ -z "$server_name" ]]; then
      echo -e -n ${WHITE}${CURSORUP}${ERASEUNTILLENDOFLINE}
      return 1
    fi
    # Проверяем корректность начального имени сайта
    if [[ "$server_name" =~ $regex ]]; then
      echo -e "${WHITE}Имя сервера ${GREEN}$server_name${WHITE} введено корректно."
      if grep -q "$server_name" ~/.ssh/config; then
        echo -e "Этот сервер уже существует в списке, выберите другой."
        echo -e -n "Введите корректное имя сервера:${GREEN}"
        read -e -p " " server_name
        continue # Пропускаем текущую итерацию цикла
      fi
      break
    else
      echo -e "${WHITE}Имя сервера ${RED}$server_name${WHITE} некорректное. "
      echo -e -n "Введите корректное имя (Enter для выхода):${GREEN}"
      read -e -p " " server_name
    fi
  done
  comment=${server_name}
  echo -e -n "${WHITE}Укажите комментарий для ключа:${GREEN}"
  read -e -p " " -i "$comment" comment
  echo -e ${WHITE}
  ssh-keygen -t ed25519 -C "$comment" -f ~/.ssh/${server_name}-key -N ''
  {
    echo
    echo "Host ${server_name}"
    echo "  Hostname ${ip_address}"
    echo "  User root"
    echo "  Compression yes"
    echo "  IdentityFile ~/.ssh/${server_name}-key"
  } >>~/.ssh/config
  echo "Пожалуйста, скопируйте следующую команду и вставьте её в терминал удалённого сервера после подключения:"
  echo -e "${LGREEN}echo '$(cat ~/.ssh/${server_name}-key.pub)' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys${WHITE}"
  echo "После этого можете продолжить работу."
  echo

  # Сортируем файл config по алфавиту
  config_file="$HOME/.ssh/config"
  temp_file="$HOME/.ssh/temp_config"
  sorted_file="$HOME/.ssh/config.sorted"

  # Создаем резервную копию файла конфигурации
  cp "$config_file" "${config_file}.bak"

  # Создаем временный файл, преобразуем все многострочные записи в однострочные
  awk 'BEGIN {
    first = 1;  # Флаг для отслеживания первой записи
}
{
    if ($1 == "Host") {
        if (!first) {
            printf "\n\n";  # Добавляем два перевода строки только если это не первая запись
        }
        first = 0;  # Сбрасываем флаг первой записи после первой обработки
        printf "%s", $0;  # Печатаем заголовок Host без начального перевода строки
    } else {
        # Удаляем начальные пробелы и табуляции, заменяем внутренние пробелы на один пробел
        gsub(/^[ \t]+|[ \t]+$/, "", $0);
        gsub(/[ \t]+/, " ", $0);
        printf "@%s", $0;  # Добавляем разделитель @
    }
} END {print "";}' "$config_file" >"$temp_file"

  # Удаление всех двойных переводов строк (пустых строк), которые могли появиться
  sed '/^$/d' "$temp_file" >"$sorted_file"

  # Сортировка строк
  sort "$sorted_file" -o "$sorted_file"

  # Преобразование обратно в многострочный формат
  awk 'BEGIN {FS="@"} {
    for (i = 1; i <= NF; i++) {
        if (i == 1) {
            print $i;  # Печать заголовка Host
        } else if (length($i) > 0) {
            print "    " $i;  # Добавление отступа и печать строки
        }
    }
    print "";  # Добавляем пустую строку после каждого блока для разделения
}' "$sorted_file" >"$config_file"

  # Очистка временных файлов
  rm -f "$temp_file" "$sorted_file"

}

mapfile -t servers < <(<~/.ssh/config grep "Host " | awk '{print $2}' | sort | grep -v '^*$')
# Добавляем "Добавить сервер" в начало массива
servers=("Добавить сервер" "${servers[@]}")
echo "Выберите сервер для подключения:"
vertical_menu "current" 2 0 30 "${servers[@]}"
choice=$?
if ((choice == 255)); then
  echo -e ${CURSORUP}"Отказ от выбора. Выход."${ERASEUNTILLENDOFLINE}
  exit
fi
if ((choice == 0)); then
  AddServer
  vertical_menu "current" 2 0 5 "Нажмите Enter"
  exit
fi
selected_server=${servers[${choice}]}
echo -e "${GREEN}${selected_server}${WHITE}"
echo "Запомните – Ctrl-D отключение от удаленного сервера."
if vertical_menu "current" 2 0 5 "Подключиться к ${selected_server}" "Выйти"
then
  ssh "$selected_server"
fi

