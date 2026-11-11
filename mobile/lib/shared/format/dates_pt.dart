/// Formatação pt-BR simples (sem dependência extra). Sempre no fuso LOCAL do
/// aparelho; o fuso do vínculo virá do servidor na integração (Etapa 3).
abstract final class DatesPt {
  static const _weekdays = [
    'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira',
    'Sexta-feira', 'Sábado', 'Domingo',
  ];
  static const _months = [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
    'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  ];

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// "Quarta-feira, 11 de novembro"
  static String longDay(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${d.day} de ${_months[d.month - 1]}';

  /// "11 de novembro"
  static String dayMonth(DateTime d) => '${d.day} de ${_months[d.month - 1]}';

  /// "11/11/2026"
  static String numeric(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  /// "08:02"
  static String hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// "Hoje, 11 de novembro" / "Ontem, 10 de novembro" / "Segunda-feira, 9 de novembro"
  static String relativeDay(DateTime d, DateTime now) {
    final diff = dateOnly(now).difference(dateOnly(d)).inDays;
    if (diff == 0) return 'Hoje, ${dayMonth(d)}';
    if (diff == 1) return 'Ontem, ${dayMonth(d)}';
    return longDay(d);
  }

  static String greeting(DateTime now) => now.hour < 12
      ? 'Bom dia'
      : now.hour < 18
          ? 'Boa tarde'
          : 'Boa noite';
}
