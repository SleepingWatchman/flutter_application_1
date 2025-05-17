import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Виджет для отображения календарной сетки, масштабируемой под размер окна.
class CalendarGrid extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;
  final DateTime? highlightedDate;
  final Function(DateTime)? onDateHighlighted;
  /// Функция для изменения текущего месяца без выбора конкретного дня
  final Function(DateTime)? onMonthChanged;

  const CalendarGrid({
    Key? key,
    required this.selectedDate,
    required this.onDateSelected,
    this.highlightedDate,
    this.onDateHighlighted,
    this.onMonthChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(selectedDate.year, selectedDate.month, 1);
    final lastDayOfMonth = DateTime(selectedDate.year, selectedDate.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final startingWeekday = firstDayOfMonth.weekday;
    final weeks = ((daysInMonth + startingWeekday - 1) / 7).ceil();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Month and year header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.cyan),
                onPressed: () {
                  final newDate = DateTime(selectedDate.year, selectedDate.month - 1, 1);
                  // Используем onMonthChanged вместо onDateSelected, если она доступна
                  if (onMonthChanged != null) {
                    onMonthChanged!(newDate);
                  } else {
                    onDateSelected(newDate);
                  }
                },
              ),
              GestureDetector(
                onTap: () => _showMonthYearPicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('MMMM yyyy', 'ru').format(selectedDate),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, color: Colors.cyan),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.cyan),
                onPressed: () {
                  final newDate = DateTime(selectedDate.year, selectedDate.month + 1, 1);
                  // Используем onMonthChanged вместо onDateSelected, если она доступна
                  if (onMonthChanged != null) {
                    onMonthChanged!(newDate);
                  } else {
                    onDateSelected(newDate);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Weekday headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
                .map((day) => SizedBox(
                      width: 40,
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.cyan,
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          // Calendar grid
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: weeks * 7,
              itemBuilder: (context, index) {
                final dayOffset = index - (startingWeekday - 1);
                final day = dayOffset + 1;
                final isCurrentMonth = day > 0 && day <= daysInMonth;
                final isToday = isCurrentMonth &&
                    day == DateTime.now().day &&
                    selectedDate.month == DateTime.now().month &&
                    selectedDate.year == DateTime.now().year;
                final isSelected = isCurrentMonth &&
                    day == selectedDate.day &&
                    selectedDate.month == selectedDate.month &&
                    selectedDate.year == selectedDate.year;
                final isHighlighted = highlightedDate != null &&
                    isCurrentMonth &&
                    day == highlightedDate!.day &&
                    selectedDate.month == highlightedDate!.month &&
                    selectedDate.year == highlightedDate!.year;

                return isCurrentMonth
                    ? GestureDetector(
                        onTap: () {
                          final selectedDay = DateTime(selectedDate.year, selectedDate.month, day);
                          // If this date is already highlighted, open it directly
                          if (highlightedDate != null && 
                              day == highlightedDate!.day && 
                              selectedDate.month == highlightedDate!.month && 
                              selectedDate.year == highlightedDate!.year) {
                            onDateSelected(selectedDay);
                          } else if (onDateHighlighted != null) {
                            // Otherwise, highlight it
                            onDateHighlighted!(selectedDay);
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? Colors.cyan.withOpacity(0.3)
                                : isToday
                                    ? Colors.cyan.withOpacity(0.1)
                                    : null,
                            border: Border.all(
                              color: isHighlighted
                                  ? Colors.cyan
                                  : isToday
                                      ? Colors.cyan.withOpacity(0.5)
                                      : Colors.grey.withOpacity(0.3),
                              width: isHighlighted ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              day.toString(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isHighlighted
                                    ? Colors.cyan
                                    : isToday
                                        ? Colors.cyan
                                        : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Container();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Открывает всплывающее окно для выбора месяца и года
  void _showMonthYearPicker(BuildContext context) {
    final currentYear = selectedDate.year;
    final currentMonth = selectedDate.month;
    
    int selectedYear = currentYear;
    int selectedMonth = currentMonth;
    
    // Список месяцев на русском языке
    final months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 
      'Май', 'Июнь', 'Июль', 'Август', 
      'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    
    // Диапазон годов для выбора (от -5 до +5 от текущего)
    final years = List<int>.generate(11, (i) => DateTime.now().year - 5 + i);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Выберите месяц и год'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Выпадающий список месяцев
                  DropdownButton<int>(
                    isExpanded: true,
                    value: selectedMonth,
                    items: List.generate(12, (index) {
                      return DropdownMenuItem<int>(
                        value: index + 1,
                        child: Text(months[index]),
                      );
                    }),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedMonth = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Выпадающий список годов
                  DropdownButton<int>(
                    isExpanded: true,
                    value: years.contains(selectedYear) ? selectedYear : years[5],
                    items: years.map((year) {
                      return DropdownMenuItem<int>(
                        value: year,
                        child: Text(year.toString()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedYear = value;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final newDate = DateTime(selectedYear, selectedMonth, 1);
                    // Используем onMonthChanged вместо onDateSelected, если она доступна
                    if (onMonthChanged != null) {
                      onMonthChanged!(newDate);
                    } else {
                      onDateSelected(newDate);
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Открыть'),
                ),
              ],
            );
          },
        );
      },
    );
  }
} 