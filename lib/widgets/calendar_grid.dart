import 'package:flutter/material.dart';

/// Виджет для отображения календарной сетки, масштабируемой под размер окна.
class CalendarGrid extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const CalendarGrid({
    Key? key,
    required this.selectedDate,
    required this.onDateSelected,
  }) : super(key: key);

  @override
  _CalendarGridState createState() => _CalendarGridState();
}

class _CalendarGridState extends State<CalendarGrid> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // Инициализируем собственный ScrollController
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    // Освобождаем ресурсы
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Текущее время и расчёт дней месяца
    DateTime now = DateTime.now();
    DateTime firstDay = DateTime(now.year, now.month, 1);
    DateTime lastDay = DateTime(now.year, now.month + 1, 0);
    int totalDays = lastDay.day;
    int startingWeekday =
        firstDay.weekday; // 1 = понедельник, ... 7 = воскресенье

    // Заголовок дней недели
    List<Widget> headerCells = [];
    List<String> weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    for (String day in weekDays) {
      headerCells.add(
        Expanded(
          child: Container(
            alignment: Alignment.center,
            child: Text(
              day,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ),
      );
    }

    // Ячейки с числами
    List<Widget> dayCells = [];
    // Пустые ячейки до первого числа месяца
    for (int i = 1; i < startingWeekday; i++) {
      dayCells.add(Container());
    }
    // Добавляем ячейки для каждого дня месяца
    for (int d = 1; d <= totalDays; d++) {
      DateTime currentDay = DateTime(now.year, now.month, d);
      bool isSelected = currentDay.year == widget.selectedDate.year &&
          currentDay.month == widget.selectedDate.month &&
          currentDay.day == widget.selectedDate.day;

      dayCells.add(
        GestureDetector(
          onTap: () => widget.onDateSelected(currentDay),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected ? Colors.cyan : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              d.toString(),
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Определяем ширину для расчёта размера ячеек
        double width = (constraints.hasBoundedWidth &&
                constraints.maxWidth != double.infinity)
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;

        if (width <= 0) return Container();
        double cellSize = width / 7;

        return Column(
          children: [
            // Заголовок дней недели (одна строка)
            Container(
              height: cellSize,
              child: Row(children: headerCells),
            ),
            // Прокручиваемая сетка для дней
            Expanded(
              child: Scrollbar(
                controller: _scrollController, // привязываем ScrollController
                thumbVisibility:
                    true, // чтобы полоса прокрутки всегда была видна (по желанию)
                child: GridView.builder(
                  controller:
                      _scrollController, // передаём контроллер в GridView
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 1, // квадратные ячейки
                  ),
                  itemCount: dayCells.length,
                  itemBuilder: (context, index) {
                    return dayCells[index];
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
} 