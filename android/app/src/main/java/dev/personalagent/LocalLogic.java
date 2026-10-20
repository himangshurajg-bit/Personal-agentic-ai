package dev.personalagent;

import java.math.BigDecimal;
import java.math.MathContext;

public final class LocalLogic {
  public static String calculate(String input) {
    if (input == null || input.length() > 200 || !input.matches("[0-9+*/(). \\-]+"))
      throw new IllegalArgumentException("Use numbers, parentheses and + − * / only.");
    Parser p = new Parser(input.replace(" ", ""));
    BigDecimal n = p.expr(0);
    if (p.i != p.s.length()) throw new IllegalArgumentException("Check the expression.");
    return n.stripTrailingZeros().toPlainString();
  }

  private static final class Parser {
    String s;
    int i;

    Parser(String s) {
      this.s = s;
    }

    boolean eat(char c) {
      if (i < s.length() && s.charAt(i) == c) {
        i++;
        return true;
      }
      return false;
    }

    BigDecimal expr(int d) {
      if (d > 24) throw new IllegalArgumentException("Too many nested parentheses.");
      BigDecimal v = term(d + 1);
      while (i < s.length()) {
        if (eat('+')) v = v.add(term(d + 1));
        else if (eat('-')) v = v.subtract(term(d + 1));
        else break;
      }
      return v;
    }

    BigDecimal term(int d) {
      BigDecimal v = factor(d + 1);
      while (i < s.length()) {
        if (eat('*')) v = v.multiply(factor(d + 1), MathContext.DECIMAL64);
        else if (eat('/')) v = v.divide(factor(d + 1), MathContext.DECIMAL64);
        else break;
      }
      return v;
    }

    BigDecimal factor(int d) {
      if (d > 30) throw new IllegalArgumentException("Expression too deeply nested.");
      if (eat('+')) return factor(d + 1);
      if (eat('-')) return factor(d + 1).negate();
      if (eat('(')) {
        BigDecimal v = expr(d + 1);
        if (!eat(')')) throw new IllegalArgumentException("Missing closing parenthesis.");
        return v;
      }
      int start = i;
      while (i < s.length() && (Character.isDigit(s.charAt(i)) || s.charAt(i) == '.')) i++;
      if (i == start) throw new IllegalArgumentException("Expected a number.");
      return new BigDecimal(s.substring(start, i), MathContext.DECIMAL64);
    }
  }

  public static String preview(String input) {
    if (input == null || input.trim().isEmpty() || input.length() > 2000)
      throw new IllegalArgumentException("Enter a plan up to 2,000 characters.");
    String[] steps = input.split(";");
    if (steps.length > 12) throw new IllegalArgumentException("Use up to 12 steps.");
    StringBuilder out = new StringBuilder("PREVIEW ONLY · nothing executed\n\n");
    int i = 0;
    for (String raw : steps) {
      String t = raw.trim();
      if (t.isEmpty()) continue;
      String lower = t.toLowerCase(java.util.Locale.ROOT);
      String label =
          lower.startsWith("calculate ")
              ? "Local calculation"
              : lower.startsWith("remember ")
                  ? "Local note · would save only on explicit action"
                  : lower.startsWith("draft ")
                      ? "Draft · owner review required, no sending available"
                      : "Unsupported · not executable in this app";
      out.append(++i).append(". ").append(label).append("\n").append(t).append("\n\n");
    }
    return out.toString();
  }
}
