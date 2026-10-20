package dev.personalagent;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Bundle;
import android.view.WindowManager;
import android.widget.*;
import org.json.*;

public class MainActivity extends Activity {
  final int ink = Color.rgb(235, 246, 255), muted = Color.rgb(167, 194, 211);
  LinearLayout body, tabs;
  SharedPreferences store;
  String page = "Studio";
  boolean reduced;

  int dp(float v) {
    return (int) (v * getResources().getDisplayMetrics().density + .5f);
  }

  public void onCreate(Bundle state) {
    super.onCreate(state);
    store = getSharedPreferences("local_agent", MODE_PRIVATE);
    reduced =
        android.provider.Settings.Global.getFloat(
                getContentResolver(), android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
            == 0;
    getWindow().setStatusBarColor(Color.rgb(12, 29, 48));
    getWindow().setNavigationBarColor(Color.rgb(12, 29, 48));
    getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    render();
  }

  GradientDrawable glass(boolean strong) {
    GradientDrawable g =
        new GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            new int[] {strong ? 0xff32627a : 0xb32d4b63, strong ? 0xff244855 : 0xb3182c43});
    g.setCornerRadius(dp(23));
    g.setStroke(dp(1), 0x99a9dbe8);
    return g;
  }

  TextView text(String value, int size, int color) {
    TextView v = new TextView(this);
    v.setText(value);
    v.setTextSize(size);
    v.setTextColor(color);
    v.setPadding(0, dp(5), 0, dp(5));
    return v;
  }

  LinearLayout col() {
    LinearLayout v = new LinearLayout(this);
    v.setOrientation(1);
    return v;
  }

  void render() {
    ScrollView scroll = new ScrollView(this);
    GradientDrawable bg =
        new GradientDrawable(
            GradientDrawable.Orientation.TL_BR, new int[] {0xff0a1830, 0xff123a49, 0xff151e3d});
    scroll.setBackground(bg);
    body = col();
    body.setPadding(dp(20), dp(34), dp(20), dp(32));
    scroll.setFillViewport(true);
    scroll.addView(body);
    setContentView(scroll);
    body.addView(text("PERSONAL AGENT / ANDROID LAB", 11, muted));
    body.addView(text("A little clarity.\nAll on your phone.", 31, ink));
    body.addView(text("Offline tools · private local storage · test build", 13, muted));
    tabs = new LinearLayout(this);
    for (String title : new String[] {"Studio", "Notes", "Drafts"}) {
      Button b =
          button(
              title,
              () -> {
                page = title;
                render();
              });
      LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, dp(53), 1);
      p.setMargins(dp(3), dp(14), dp(3), dp(12));
      tabs.addView(b, p);
    }
    body.addView(tabs);
    if (page.equals("Studio")) studio();
    else if (page.equals("Notes")) notes();
    else drafts();
    body.addView(
        text(
            "No AI model, network, background service or device control. Draft approval never sends"
                + " a message. Data stays in this app on this device.",
            12,
            muted));
  }

  LinearLayout card(String title, String desc) {
    LinearLayout c = col();
    c.setBackground(glass(false));
    c.setElevation(dp(6));
    c.setPadding(dp(18), dp(15), dp(18), dp(18));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.setMargins(0, dp(8), 0, dp(10));
    body.addView(c, p);
    c.addView(text(title, 22, ink));
    c.addView(text(desc, 13, muted));
    return c;
  }

  EditText field(LinearLayout c, String hint, boolean multi) {
    EditText e = new EditText(this);
    e.setHint(hint);
    e.setHintTextColor(0xff9bb7c7);
    e.setTextColor(ink);
    e.setTextSize(16);
    e.setPadding(dp(14), dp(12), dp(14), dp(12));
    e.setBackground(glass(false));
    e.setSingleLine(!multi);
    e.setMaxLines(multi ? 5 : 1);
    e.setFilters(new android.text.InputFilter[] {new android.text.InputFilter.LengthFilter(2000)});
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.setMargins(0, dp(12), 0, dp(8));
    c.addView(e, p);
    e.setContentDescription(hint);
    return e;
  }

  Button button(String label, Runnable action) {
    Button b = new Button(this);
    b.setText(label);
    b.setTextColor(ink);
    b.setTextSize(13);
    b.setAllCaps(false);
    b.setMinHeight(dp(48));
    b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x6689e7eb), glass(true), null));
    b.setOnClickListener(
        v -> {
          if (!reduced)
            b.animate()
                .scaleX(.98f)
                .scaleY(.98f)
                .setDuration(70)
                .withEndAction(() -> b.animate().scaleX(1).scaleY(1).setDuration(140).start())
                .start();
          action.run();
        });
    return b;
  }

  void addButton(LinearLayout c, String label, Runnable r) {
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, dp(49));
    p.setMargins(0, dp(10), 0, dp(3));
    c.addView(button(label, r), p);
  }

  void studio() {
    LinearLayout calc =
        card("01 / Calculate", "A bounded local calculator. No scripts or internet.");
    EditText expr = field(calc, "e.g. (12 + 8) / 4", false);
    TextView result = text("Your result appears here", 17, ink);
    addButton(
        calc,
        "Calculate",
        () -> {
          try {
            result.setText(LocalLogic.calculate(expr.getText().toString()));
          } catch (Exception e) {
            result.setText(
                "Check the expression. Division by zero and unsupported inputs are not allowed.");
          }
        });
    calc.addView(result);
    LinearLayout preview =
        card(
            "02 / Plan preview",
            "See steps before doing anything. Preview does not save or execute.");
    EditText goal = field(preview, "calculate 12 * 3; remember Practice Python", true);
    TextView steps = text("Nothing executed", 14, ink);
    addButton(
        preview,
        "Preview safely",
        () -> {
          try {
            steps.setText(LocalLogic.preview(goal.getText().toString()));
          } catch (Exception e) {
            steps.setText(e.getMessage());
          }
        });
    preview.addView(steps);
  }

  JSONArray list(String key) {
    try {
      return new JSONArray(store.getString(key, "[]"));
    } catch (Exception e) {
      return new JSONArray();
    }
  }

  void persist(String key, JSONArray v) {
    store.edit().putString(key, v.toString()).apply();
  }

  void toast(String s) {
    Toast.makeText(this, s, Toast.LENGTH_SHORT).show();
  }

  void notes() {
    LinearLayout c = card("Your notes", "Saved only on this phone. No cloud sync.");
    EditText note = field(c, "Write a note", true);
    addButton(
        c,
        "Save note",
        () -> {
          String s = note.getText().toString().trim();
          if (s.isEmpty()) {
            toast("Write a note first");
            return;
          }
          JSONArray a = list("notes");
          if (a.length() >= 100) {
            toast("This test app holds up to 100 notes");
            return;
          }
          a.put(s);
          persist("notes", a);
          render();
        });
    JSONArray a = list("notes");
    if (a.length() == 0) c.addView(text("A quiet place for your first idea.", 15, muted));
    for (int i = a.length() - 1; i >= 0; i--) {
      final int idx = i;
      LinearLayout n = card("Note " + (i + 1), a.optString(i));
      addButton(
          n,
          "Delete note",
          () ->
              new android.app.AlertDialog.Builder(this)
                  .setMessage("Delete this local note?")
                  .setNegativeButton("Keep", null)
                  .setPositiveButton(
                      "Delete",
                      (d, w) -> {
                        JSONArray old = list("notes");
                        old.remove(idx);
                        persist("notes", old);
                        render();
                      })
                  .show());
    }
  }

  void drafts() {
    LinearLayout c =
        card(
            "Prepare, then review",
            "Local draft storage only. No account connection or send operation.");
    EditText to = field(c, "Recipient label (not contacted)", false),
        message = field(c, "Message draft", true);
    addButton(
        c,
        "Prepare draft",
        () -> {
          String t = to.getText().toString().trim(), m = message.getText().toString().trim();
          if (t.isEmpty() || m.isEmpty()) {
            toast("Add a recipient label and message");
            return;
          }
          JSONArray a = list("drafts");
          if (a.length() >= 100) {
            toast("This test app holds up to 100 drafts");
            return;
          }
          try {
            JSONObject d = new JSONObject();
            d.put("to", t);
            d.put("message", m);
            d.put("status", "pending_review");
            d.put("expires", System.currentTimeMillis() + 3600000L);
            a.put(d);
            persist("drafts", a);
            render();
          } catch (Exception e) {
            toast("Draft could not be saved");
          }
        });
    JSONArray a = list("drafts");
    for (int i = a.length() - 1; i >= 0; i--) {
      JSONObject d = a.optJSONObject(i);
      if (d == null) continue;
      final int idx = i;
      String status = d.optString("status");
      if (status.equals("pending_review") && System.currentTimeMillis() >= d.optLong("expires", 0))
        status = "expired";
      LinearLayout item =
          card(
              d.optString("to"),
              status.equals("approved_not_sent")
                  ? "APPROVED · NOT SENT"
                  : status.equals("rejected")
                      ? "REJECTED · NOT SENT"
                      : status.equals("expired")
                          ? "EXPIRED · NOT SENT"
                          : "AWAITING YOUR REVIEW · expires after 1 hour");
      item.addView(text(d.optString("message"), 17, ink));
      if (status.equals("pending_review")) {
        addButton(
            item, "Approve locally · do not send", () -> updateDraft(idx, "approved_not_sent"));
        addButton(item, "Reject draft", () -> updateDraft(idx, "rejected"));
      }
    }
  }

  void updateDraft(int i, String state) {
    JSONArray a = list("drafts");
    try {
      JSONObject d = a.getJSONObject(i);
      if (!d.getString("status").equals("pending_review")) return;
      if (System.currentTimeMillis() >= d.optLong("expires", 0)) {
        d.put("status", "expired");
        persist("drafts", a);
        render();
        toast("Draft review expired; prepare a new draft");
        return;
      }
      d.put("status", state);
      persist("drafts", a);
      render();
    } catch (Exception e) {
      toast("Draft is unavailable");
    }
  }
}
