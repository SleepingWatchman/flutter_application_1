import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Виджет для отображения календарной сетки, масштабируемой под размер окна.
class CalendarGrid extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;
  final DateTime? highlightedDate;
  final Function(DateTime)? onDateHighlighted;

  const CalendarGrid({
    Key? key,
    required this.selectedDate,
    required this.onDateSelected,
    this.highlightedDate,
    this.onDateHighlighted,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
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
              Text(
                DateFormat('MMMM yyyy', 'ru').format(now),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
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
                    now.month == DateTime.now().month &&
                    now.year == DateTime.now().year;
                final isSelected = isCurrentMonth &&
                    day == selectedDate.day &&
                    now.month == selectedDate.month &&
                    now.year == selectedDate.year;
                final isHighlighted = highlightedDate != null &&
                    isCurrentMonth &&
                    day == highlightedDate!.day &&
                    now.month == highlightedDate!.month &&
                    now.year == highlightedDate!.year;

                return isCurrentMonth
                    ? GestureDetector(
                        onTap: () {
                          final selectedDay = DateTime(now.year, now.month, day);
                          // If this date is already highlighted, open it directly
                          if (highlightedDate != null && 
                              day == highlightedDate!.day && 
                              now.month == highlightedDate!.month && 
                              now.year == highlightedDate!.year) {
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
} 