import dev.personalagent.LocalLogic;

public class LocalLogicTest {
  static int n;

  static void eq(String a, String b) {
    n++;
    if (!a.equals(b)) throw new AssertionError(a + " != " + b);
  }

  static void invalid(String a) {
    n++;
    try {
      LocalLogic.calculate(a);
      throw new AssertionError("accepted " + a);
    } catch (IllegalArgumentException | ArithmeticException expected) {
    }
  }

  public static void main(String[] args) {
    eq(LocalLogic.calculate("(12 + 8) / 4"), "5");
    eq(LocalLogic.calculate("-3 * (2 + 4)"), "-18");
    eq(LocalLogic.calculate("0.1 + 0.2"), "0.3");
    eq(LocalLogic.calculate("2+3*4"), "14");
    invalid("1/0");
    invalid("foo()");
    invalid("1+2 garbage");
    invalid("1..2");
    invalid("(1");
    invalid("9".repeat(201));
    invalid("(".repeat(40) + "1" + ")".repeat(40));
    String p = LocalLogic.preview("calculate 1+2; remember idea; draft hi; open instagram");
    for (String t :
        new String[] {
          "PREVIEW ONLY", "Local calculation", "Local note", "owner review required", "Unsupported"
        }) {
      n++;
      if (!p.contains(t)) throw new AssertionError(t);
    }
    System.out.println(n + " Android local-logic assertions passed");
  }
}
