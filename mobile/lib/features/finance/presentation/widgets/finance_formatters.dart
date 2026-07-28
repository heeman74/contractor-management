/// Shared money and percent formatters for the finance summary widgets.
/// Backend Decimal-as-Strings in, display strings out — no float math ever.
library;

const financeFigureSeparator = ' · ';

/// "21.0" -> "21", "8.3" -> "8.3" — one backend decimal, trailing .0 dropped.
String formatMarginPercent(String percent) {
  return percent.endsWith('.0')
      ? percent.substring(0, percent.length - 2)
      : percent;
}

/// "-350.00" -> "-$350.00", "4200.00" -> "$4200.00" (sign precedes the
/// symbol).
String formatMarginDollars(String amount) {
  return amount.startsWith('-')
      ? '-\$${amount.substring(1)}'
      : '\$$amount';
}

/// The backend percent_used string with the trailing-".0" rule applied:
/// "82.0" -> "82", "82.5" -> "82.5", "112.0" -> "112".
String formatPercentUsed(String percentUsed) => formatMarginPercent(percentUsed);
