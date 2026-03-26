// ============================================================
// EVraahein Waitlist – Google Apps Script
// ============================================================
// SETUP:
//   1. Open your Google Sheet → Extensions → Apps Script
//   2. Paste this entire file, replacing any existing code
//   3. Save (Ctrl+S)
//   4. Click Deploy → New deployment
//      - Type: Web app
//      - Execute as: Me
//      - Who has access: Anyone
//   5. Click Deploy → copy the Web App URL
//   6. Paste that URL into index.html where indicated (SCRIPT_URL)
// ============================================================

const NOTIFY_EMAIL = "tlventuresopc@gmail.com";
const SHEET_NAME   = "Waitlist";             // tab name in your Sheet

function doPost(e) {
  try {
    const data      = JSON.parse(e.postData.contents);
    const email     = (data.email || "").trim();
    const timestamp = new Date().toLocaleString("en-IN", { timeZone: "Asia/Kolkata" });

    if (!email) return respond({ ok: false, error: "No email provided" });

    // ── Write to Sheet ──────────────────────────────────────
    const ss    = SpreadsheetApp.getActiveSpreadsheet();
    let   sheet = ss.getSheetByName(SHEET_NAME);
    if (!sheet) {
      sheet = ss.insertSheet(SHEET_NAME);
      sheet.appendRow(["Timestamp (IST)", "Email"]);          // header row
    }
    sheet.appendRow([timestamp, email]);

    // ── Notify by email ─────────────────────────────────────
    MailApp.sendEmail({
      to:      NOTIFY_EMAIL,
      subject: "🚗⚡ New EVraahein Waitlist Signup",
      body: [
        "A new user joined the EVraahein waitlist!",
        "",
        "Email    : " + email,
        "Time (IST): " + timestamp,
        "",
        "View the full list: " + SpreadsheetApp.getActiveSpreadsheet().getUrl()
      ].join("\n")
    });

    return respond({ ok: true });

  } catch (err) {
    return respond({ ok: false, error: err.message });
  }
}

// Allow preflight CORS checks from the browser
function doGet(e) {
  return respond({ ok: true, status: "EVraahein waitlist API is live." });
}

function respond(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
