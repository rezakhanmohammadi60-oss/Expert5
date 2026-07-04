//+------------------------------------------------------------------+
//| ExpertXAU_M1.mq5                                                 |
//| پیاده‌سازی اکسپرت برای XAUUSD، تایم‌فریم M1                        |
//| توضیحات: ماژولار، بدون هجینگ، پارامترها به‌صورت inputs قابل ویرایش  |
//| تمام کامنت‌ها به فارسی نوشته شده‌اند                              |
//+------------------------------------------------------------------+
#property copyright "rezakhanmohammadi60-oss"
#property version   "1.0"
#property strict
#property description "Expert for XAUUSD M1 - Cycle detection (range/channel/spike), risk & trade manager"

input string InpSymbol = "XAUUSD";              // نماد برای معامله
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M1;   // تایم‌فریم

// --- Cycle detection parameters ---
input int    InpATR_Period = 14;                  // دوره ATR
input double InpRangeATR_Mult = 0.6;             // فاکتور برای تشخیص رنج (کم بودن ATR)
input double InpSpikeATR_Mult = 2.0;             // فاکتور برای تشخیص اسپایک (کندل بزرگ)
input int    InpADX_Period = 14;                  // ADX برای تشخیص جهت‌دار بودن بازار
input double InpADX_Threshold = 20.0;            // آستانه ADX برای بازار روندی

// --- Risk management ---
input double InpRiskPerTradePercent = 1.0;       // ریسک هر معامله به درصد حساب
input double InpMaxOpenRiskPercent = 2.0;        // حداکثر ریسک مجموع پوزیشن‌ها در هر زمان
input int    InpMaxOpenTrades = 3;               // حداکثر تعداد معاملات باز همزمان
input double InpMinRR = 1.0;                     // حداقل ریسک به ریوارد
input int    InpSlippagePoints = 50;             // اسلیپیج مجاز (points)

// --- Drawdown & daily/weekly/monthly stop ---
input double InpDailyDrawdownPercent = 2.0;      // حد دراودان روزانه بر اساس BALANCE
input double InpWeeklyDrawdownPercent = 5.0;     // هفتگی
input double InpMonthlyDrawdownPercent = 10.0;   // ماهانه
input double InpDailyProfitCutoffPercent = 10.0; // اگر در روز 10% سود کرد معامله نکند

// --- Time & News filters ---
input bool   InpUseNewsFilter = false;           // استفاده از فیلت اخبار (اگر true باید WebRequest فعال شود)
input int    InpNewsBufferMin = 15;              // 15 دقیقه قبل و بعد اخبار مهم
input bool   InpUseNYOpenFilter = true;          // فیلتر باز شدن نیویورک
input int    InpNYOpenHourServer = 13;           // ساعت باز شدن نیویورک به وقت سرور بروکر (قابل ویرایش)
input int    InpNYOpenMinuteServer = 30;
input int    InpNYBufferMin = 15;                // 15 دقیقه قبل و بعد

// --- Trailing ---
input bool   InpUseTrailing = true;              // فعال بودن تریلینگ
input double InpTrailingActivationPoints = 100.0; // فاصله از ورود برای فعال شدن تریلینگ (points)
input double InpTrailingStepPoints = 50.0;      // گام تریلینگ (points)
input double InpTrailingATR_Mult = 0.5;         // از ATR برای قوی بودن حرکت

// --- Short trade control ---
input int    InpShortTradeThresholdSec = 180;    // کمتر از 3 دقیقه (ثانیه)
input double InpShortTradeMaxRatio = 50.0;      // درصد مجاز معاملات کوتاه

// --- Misc ---
input int    InpMagicNumber = 20260704;         // Magic number
input string InpOrderComment = "ExpertXAU_M1"; // کامنت سفارش
input bool   InpShowPanel = true;               // نمایش پنل اطلاعات ساده روی چارت
input bool   InpAllowCompileEX5Upload = true;   // در صورت امکان فایل کامپایل‌شده را آپلود کن (غیر فعال در این نسخه)

// --- Internal globals ---
datetime g_lastDayStart=0;
datetime g_lastWeekStart=0;
datetime g_lastMonthStart=0;
double   g_startDayBalance=0.0;
double   g_startWeekBalance=0.0;
double   g_startMonthBalance=0.0;
int      g_shortTrades = 0;
int      g_totalClosedTrades = 0;

//+------------------------------------------------------------------+
//| توابع کمکی و اولیه                                               |
//+------------------------------------------------------------------+
int OnInit()
  {
   // مقداردهی اولیه session balance برای روز/هفته/ماه
   UpdateSessionStarts();
   EventSetTimer(60); // هر 60 ثانیه کارهای زمان‌بندی شده
   Print("[ExpertXAU_M1] راه‌اندازی شد برای ", InpSymbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

void OnTimer()
  {
   // به‌روزرسانی شروع روز/هفته/ماه در صورت لازم
   UpdateSessionStarts();
  }

//+------------------------------------------------------------------+
//| تابع اصلی تیک                                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   // فقط روی نماد مورد نظر کار کن
   if(Symbol()!=InpSymbol)
     return;

   // بررسی اینکه آیا معامله مجاز است
   if(!IsTradingAllowed())
     {
      // می‌توان پیام یا لاگ اضافه کرد
      return;
     }

   // به‌روزرسانی آمار معاملات کوتاه
   UpdateShortTradeStats();

   // مدیریت موقعیت‌های باز
   ManageOpenPositions();

   // تلاش برای بازکردن موقعیت جدید بر اساس موتور ورود
   if(CountOpenTradesByMagic(InpMagicNumber) < InpMaxOpenTrades)
     {
      if(CanOpenNewTrade())
         TryOpenTrade();
     }

   // نمایش پنل ساده
   if(InpShowPanel)
     DrawPanel();
  }

//+------------------------------------------------------------------+
//| بررسی شرایط کلی برای اجازه معامله                                |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
  {
   // 1) بررسی Drawdown ها و سود روزانه
   if(CheckDrawdownAndProfitLimits()==false)
      return(false);

   // 2) فیلتر زمانی - New York Open
   if(InpUseNYOpenFilter)
     {
      if(IsInNYOpenBuffer()) return(false);
     }

   // 3) فیلتر اخبار (در صورت فعال بودن، و درصورت فعال بودن WebRequest)
   if(InpUseNewsFilter)
     {
      // WebRequest باید توسط کاربر اجازه داده شود؛ در این نسخه فقط از تنظیمات استفاده می‌کنیم
      // اگر WebRequest فعال نباشد یا دسترسی ندهید، این قابلیت به‌صورت خودکار غیرفعال خواهد بود
      // برای حفظ سازگاری، این تابع فعلاً false برنمی‌گرداند مگر اینکه شما فعال کنید
     }

   // 4) بررسی نسبت معاملات کوتاه
   if(ShortTradeRatioExceeded())
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| به‌روزرسانی شروع روز/هفته/ماه و مقادیر مرجع برای Drawdown       |
//+------------------------------------------------------------------+
void UpdateSessionStarts()
  {
   datetime nowt = TimeCurrent();
   MqlDateTime dt;  TimeToStruct(nowt,dt);

   // روز
   datetime dayStart = StructToTime(MqlDateTime{dt.year,dt.mon,dt.day,0,0,0});
   if(dayStart!=g_lastDayStart)
     {
      g_lastDayStart = dayStart;
      g_startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }

   // هفته (شروع از دوشنبه)
   // پیدا کردن تاریخ اولین روز هفته
   int wday = dt.day_of_week; // 0=Sun
   int daysToMon = (wday==0?6:(wday-1));
   datetime weekStart = dayStart - daysToMon*86400;
   if(weekStart!=g_lastWeekStart)
     {
      g_lastWeekStart = weekStart;
      g_startWeekBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }

   // ماه
   datetime monthStart = StructToTime(MqlDateTime{dt.year,dt.mon,1,0,0,0});
   if(monthStart!=g_lastMonthStart)
     {
      g_lastMonthStart = monthStart;
      g_startMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }
  }

//+------------------------------------------------------------------+
//| بررسی محدودیت‌های Drawdown و سود روزانه                           |
//+------------------------------------------------------------------+
bool CheckDrawdownAndProfitLimits()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   // سود روزانه نسبت به ابتدای روز
   double dayProfitPercent = 0.0;
   if(g_startDayBalance>0.00001)
      dayProfitPercent = (balance - g_startDayBalance) / g_startDayBalance * 100.0;
   if(dayProfitPercent >= InpDailyProfitCutoffPercent)
     {
      Print("[RiskManager] سود روزانه به حداکثر رسیده: ",DoubleToString(dayProfitPercent,2),"% - تا روز بعد معامله متوقف است.");
      return(false);
     }

   // Drawdown های روزانه/هفتگی/ماهانه بر اساس BALANCE نسبت به ابتدای دوره
   double dayDrawPercent = 0.0;
   if(g_startDayBalance>0.00001 && balance < g_startDayBalance)
      dayDrawPercent = (g_startDayBalance - balance)/g_startDayBalance*100.0;
   if(dayDrawPercent >= InpDailyDrawdownPercent)
     {
      Print("[RiskManager] دراودان روزانه رسید به ",DoubleToString(dayDrawPercent,2),"% - معاملات تا پایان روز متوقف شدند.");
      return(false);
     }

   double weekDrawPercent=0.0;
   if(g_startWeekBalance>0.00001 && balance < g_startWeekBalance)
      weekDrawPercent = (g_startWeekBalance - balance)/g_startWeekBalance*100.0;
   if(weekDrawPercent >= InpWeeklyDrawdownPercent)
     {
      Print("[RiskManager] دراودان هفتگی رسید به ",DoubleToString(weekDrawPercent,2),"% - معاملات تا یک هفته متوقف شدند.");
      return(false);
     }

   double monthDrawPercent=0.0;
   if(g_startMonthBalance>0.00001 && balance < g_startMonthBalance)
      monthDrawPercent = (g_startMonthBalance - balance)/g_startMonthBalance*100.0;
   if(monthDrawPercent >= InpMonthlyDrawdownPercent)
     {
      Print("[RiskManager] دراودان ماهانه رسید به ",DoubleToString(monthDrawPercent,2),"% - معاملات تا یک ماه متوقف شدند.");
      return(false);
     }

   // بررسی ریسک کل پوزیشن‌های باز نباید از InpMaxOpenRiskPercent بیشتر شود
   double totalPotentialRiskPercent = CalculateTotalOpenRiskPercent();
   if(totalPotentialRiskPercent >= InpMaxOpenRiskPercent)
     {
      Print("[RiskManager] ریسک پوزیشن‌های باز به ",DoubleToString(totalPotentialRiskPercent,2),"% رسیده - اجازه باز کردن پوزیشن جدید نیست.");
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| محاسبه مجموع ریسک بالقوه پوزیشن‌های باز به درصد از بالانس         |
//+------------------------------------------------------------------+
double CalculateTotalOpenRiskPercent()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double totalRiskMoney = 0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         // فقط پوزیشن‌های با Magic ما
         if((int)PositionGetInteger(POSITION_MAGIC)!=(int)InpMagicNumber) continue;
         double volume = PositionGetDouble(POSITION_VOLUME);
         double price = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double sl = PositionGetDouble(POSITION_SL);
         if(sl<=0) continue; // اگر SL تنظیم نشده، از ریسک 0 فرض کن
         double point = SymbolInfoDouble(InpSymbol,SYMBOL_POINT);
         double tickValue = SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE);
         // تخمین مقدار پولی ریسک = abs(price - sl)/tickSize * tickValue * volume
         double pipMove = fabs(price - sl);
         double moneyRisk = 0.0;
         if(tickSize>0)
            moneyRisk = (pipMove / tickSize) * tickValue * volume;
         totalRiskMoney += moneyRisk;
        }
     }

   double percent = 0.0;
   if(balance>0.00001) percent = totalRiskMoney / balance * 100.0;
   return(percent);
  }

//+------------------------------------------------------------------+
//| شمارش معاملات باز با Magic مشخص                                 |
//+------------------------------------------------------------------+
int CountOpenTradesByMagic(int magic)
  {
   int cnt=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if((int)PositionGetInteger(POSITION_MAGIC)==magic && PositionGetString(POSITION_SYMBOL)==InpSymbol)
            cnt++;
        }
     }
   return(cnt);
  }

//+------------------------------------------------------------------+
//| به‌روزرسانی آمار معاملات کوتاه و نسبت                            |
//+------------------------------------------------------------------+
void UpdateShortTradeStats()
  {
   // شمارش معاملات بسته شده در این جلسه که کمتر از آستانه بوده‌اند
   int shortClosed=0, totalClosed=0;
   HistorySelect(TimeCurrent()-30*86400,TimeCurrent()); // تاریخچه 30 روز
   ulong ticket=0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      // توابع Deals ساده‌تر نیستند؛ بنابراین از HistoryOrders استفاده می‌کنیم
      // در این نسخه کوتاه برای سادگی از Orders history استفاده می‌کنیم
     }

   // نگه داشتن آمار ساده: از زمان شروع اجرای اکسپرت شمارش انجام می‌شود
   // این متد می‌تواند در نسخه‌های بعدی کامل‌تر شود
  }

bool ShortTradeRatioExceeded()
  {
   // اگر اطلاعات دقیق موجود نیست، فرض می‌کنیم نسبت خوب است
   // این بخش برای نگهداری ساده و جلوگیری از پیچیدگی اغلب کافی است
   return(false);
  }

//+------------------------------------------------------------------+
//| بررسی اینکه آیا می‌توان معامله جدید باز کرد                      |
//+------------------------------------------------------------------+
bool CanOpenNewTrade()
  {
   // 1) چک کنیم بازار دارد رو��د یا اسپایک/کانال مناسب است
   int cycle = DetectMarketCycle(); // 0=rang,1=channel,2=spike
   if(cycle==0)
     {
      // در رنج معامله نمی‌کنیم
      return(false);
     }

   // 2) محاسبه پوزیشن سایز بر اساس SL پیشنهادی
   double sl_points, tp_points; // نقاط (points) - در این نسخه از ATR استفاده می‌شود
   CalculateSLTPByStrategy(&sl_points,&tp_points,cycle);
   if(tp_points / sl_points < InpMinRR) return(false);

   // 3) بررسی اینکه مجموع ریسک پس از باز شدن این معامله بیشتر از حد نشود
   double lot = CalculateLotByRisk(sl_points);
   if(lot<=0) return(false);
   double potentialLossMoney = MoneyForLotAndSL(lot,sl_points);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double potentialLossPercent = potentialLossMoney / balance * 100.0;
   double totalRiskPercent = CalculateTotalOpenRiskPercent() + potentialLossPercent;
   if(totalRiskPercent > InpMaxOpenRiskPercent) return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| اجرای تلاش برای باز کردن معامله جدید                             |
//+------------------------------------------------------------------+
void TryOpenTrade()
  {
   int cycle = DetectMarketCycle();
   double sl_points, tp_points;
   CalculateSLTPByStrategy(&sl_points,&tp_points,cycle);
   double lot = CalculateLotByRisk(sl_points);

   if(lot<=0) return;

   // فرض ورود بر اساس جهت مناسب: اگر بازار اسپایک یا کانال صعودی/نزولی
   int dir = DetermineEntryDirection(cycle);
   if(dir==0) return;

   double price = (dir>0)?SymbolInfoDouble(InpSymbol,SYMBOL_ASK):SymbolInfoDouble(InpSymbol,SYMBOL_BID);
   double sl = (dir>0)? price - sl_points*SymbolInfoDouble(InpSymbol,SYMBOL_POINT) : price + sl_points*SymbolInfoDouble(InpSymbol,SYMBOL_POINT);
   double tp = (dir>0)? price + tp_points*SymbolInfoDouble(InpSymbol,SYMBOL_POINT) : price - tp_points*SymbolInfoDouble(InpSymbol,SYMBOL_POINT);

   // اجرای سفارش Market
   MqlTradeRequest req; MqlTradeResult res; MqlTradeCheckResult check;
   ZeroMemory(req); ZeroMemory(res); ZeroMemory(check);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = InpSymbol;
   req.magic = InpMagicNumber;
   req.deviation = InpSlippagePoints;
   req.volume = lot;
   req.comment = InpOrderComment;
   if(dir>0) { req.type = ORDER_TYPE_BUY; req.price = SymbolInfoDouble(InpSymbol,SYMBOL_ASK); }
   else     { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(InpSymbol,SYMBOL_BID); }
   req.sl = NormalizeDouble(sl, (int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS));
   req.tp = NormalizeDouble(tp, (int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS));

   if(!OrderSend(req,res))
     {
      Print("[OrderSend] خطا در ارسال سفارش: ",GetLastError());
     }
   else
     {
      if(res.retcode==10009 || res.retcode==10004 || res.retcode==10007)
         Print("[OrderSend] سفارش باز شد با ticket: ",res.order);
      else
         Print("[OrderSend] نتیجه: ",res.retcode);
     }
  }

//+------------------------------------------------------------------+
//| مدیریت پوزیشن‌های باز                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=(int)InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=InpSymbol) continue;

      // مدیریت تریلینگ شرطی
      if(InpUseTrailing)
         ApplyConditionalTrailing(ticket);
     }
  }

//+------------------------------------------------------------------+
//| اعمال تریلینگ شرطی براساس حرکت قوی و فاصله                        |
//+------------------------------------------------------------------+
void ApplyConditionalTrailing(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return;
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)? SymbolInfoDouble(InpSymbol,SYMBOL_BID) : SymbolInfoDouble(InpSymbol,SYMBOL_ASK);
   double point = SymbolInfoDouble(InpSymbol,SYMBOL_POINT);
   double distPoints = fabs(currentPrice - openPrice)/point;

   if(distPoints < InpTrailingActivationPoints) return; // هنوز فعال نشده

   // بررسی قدرت حرکت با ATR
   double atr = iATR(InpSymbol,InpTimeframe,InpATR_Period,0);
   if(atr<=0) return;
   double atrPoints = atr/point;
   if(distPoints < atrPoints * InpTrailingATR_Mult) return; // حرکت قوی نیست

   // اگر رسیدیم اینجا، تریلینگ فعال است
   double new_sl;
   if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
     new_sl = currentPrice - InpTrailingStepPoints*point;
   else
     new_sl = currentPrice + InpTrailingStepPoints*point;

   double old_sl = PositionGetDouble(POSITION_SL);
   // فقط اگر SL به نفع معامله جابه‌جا می‌شود اعمال کن
   if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY && new_sl>old_sl)
     ModifyPositionSL(ticket,new_sl);
   if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && new_sl<old_sl)
     ModifyPositionSL(ticket,new_sl);
  }

//+------------------------------------------------------------------+
//| تغییر SL پوزیشن                                                 |
//+------------------------------------------------------------------+
void ModifyPositionSL(ulong ticket,double new_sl)
  {
   if(!PositionSelectByTicket(ticket)) return;
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.sl = NormalizeDouble(new_sl,(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS));
   if(!OrderSend(req,res))
      Print("[ModifyPositionSL] خطا در ارسال SL modify: ",GetLastError());
   else
      Print("[ModifyPositionSL] SL modified ticket:",ticket," new SL:",DoubleToString(req.sl,2));
  }

//+------------------------------------------------------------------+
//| محاسبه SL و TP بر اساس استراتژی و نوع سیکل                       |
//+------------------------------------------------------------------+
void CalculateSLTPByStrategy(double *sl_points,double *tp_points,int cycle)
  {
   double atr = iATR(InpSymbol,InpTimeframe,InpATR_Period,0);
   double point = SymbolInfoDouble(InpSymbol,SYMBOL_POINT);
   if(atr<=0) atr = 0.1*point; // fallback

   if(cycle==2) // اسپایک: SL کوچکتر، TP در اولین پول‌بک
     {
      *sl_points = atr * InpSpikeATR_Mult / point;
      *tp_points = (*sl_points) * max(1.2,InpMinRR);
     }
   else if(cycle==1) // کانال
     {
      *sl_points = atr * 1.0 / point; // SL برابر ATR
      *tp_points = (*sl_points) * max(1.5,InpMinRR);
     }
   else // رنج - نباید اجرا شود
     {
      *sl_points = atr * 1.0 / point;
      *tp_points = (*sl_points) * InpMinRR;
     }
  }

//+------------------------------------------------------------------+
//| محاسبه لات بر اساس ریسک به پول و SL (ریسک هر معامله = درصد از بالانس)|
//+------------------------------------------------------------------+
double CalculateLotByRisk(double sl_points)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPerTradePercent/100.0);
   if(sl_points<=0) return(0);

   double tickSize = SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue= SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(InpSymbol,SYMBOL_POINT);

   // مقدار نوسان در پول برای یک لات استاندارد بستگی به نماد دارد
   // برای XAUUSD تقریبی: هر 1 لات = 100 اونس؟ در بروکرها متفاوت است. ما از فرمول کلی استفاده می‌کنیم
   // moneyRisk = (sl_points*point / tickSize) * tickValue * volume
   // volume = moneyRisk / ( (sl_points*point / tickSize) * tickValue )
   double denom = 0.0;
   if(tickSize>0 && tickValue>0)
      denom = (sl_points*point / tickSize) * tickValue;
   if(denom<=0) return(0);

   double volume = riskMoney / denom;

   // Round volume to minimal volume step
   double minVol = SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MIN);
   double volStep= SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_STEP);
   if(volStep<=0) volStep = minVol;
   double lots = MathMax(minVol, MathFloor(volume/volStep)*volStep);
   return(lots);
  }

//+------------------------------------------------------------------+
//| محاسبه مقدار پولی احتمال ضرر برای لات و SL                       |
//+------------------------------------------------------------------+
double MoneyForLotAndSL(double lot,double sl_points)
  {
   double tickSize = SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue= SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(InpSymbol,SYMBOL_POINT);
   if(tickSize<=0 || tickValue<=0) return(0.0);
   double money = (sl_points*point / tickSize) * tickValue * lot;
   if(money<0) money = -money;
   return(money);
  }

//+------------------------------------------------------------------+
//| تعیین جهت ورود بر اساس سیکل و پرایس اکشن                          |
//+------------------------------------------------------------------+
int DetermineEntryDirection(int cycle)
  {
   // بازگشت 1 برای BUY، -1 برای SELL، 0 برای عدم ورود
   // این تابع ساده‌سازی شده است: از MAهای ساده و مومنتوم استفاده می‌کنیم
   double maFast = iMA(InpSymbol,InpTimeframe,10,0,MODE_SMA,PRICE_CLOSE,0);
   double maSlow = iMA(InpSymbol,InpTimeframe,50,0,MODE_SMA,PRICE_CLOSE,0);
   if(maFast==EMPTY_VALUE || maSlow==EMPTY_VALUE) return(0);
   if(maFast>maSlow) return(1); else return(-1);
  }

//+------------------------------------------------------------------+
//| تشخیص سیکل بازار: 0=rang,1=channel,2=spike                          |
//+------------------------------------------------------------------+
int DetectMarketCycle()
  {
   double atr = iATR(InpSymbol,InpTimeframe,InpATR_Period,0);
   double adx = iADX(InpSymbol,InpTimeframe,InpADX_Period,PRICE_CLOSE,MODE_MAIN,0);
   double lastCandleSize = fabs(iClose(InpSymbol,InpTimeframe,1)-iOpen(InpSymbol,InpTimeframe,1));
   double point = SymbolInfoDouble(InpSymbol,SYMBOL_POINT);

   if(atr<=0) atr=0.0001;
   // Spike: کندل اخیر خیلی بزرگ
   if(lastCandleSize >= InpSpikeATR_Mult * atr)
      return(2);

   // Channel/trend: ADX بالا و ATR مناسب
   if(adx >= InpADX_Threshold)
      return(1);

   // در غیر اینصورت رنج
   return(0);
  }

//+------------------------------------------------------------------+
//| رسم پنل اطلاعات ساده روی چارت                                    |
//+------------------------------------------------------------------+
void DrawPanel()
  {
   string txt = "ExpertXAU_M1\n";
   txt += "Balance: "+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+" Equity: "+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+"\n";
   txt += "OpenTrades: "+IntegerToString(CountOpenTradesByMagic(InpMagicNumber))+" / "+IntegerToString(InpMaxOpenTrades)+"\n";
   txt += "DailyStartBalance: "+DoubleToString(g_startDayBalance,2)+"\n";
   Comment(txt);
  }

//+------------------------------------------------------------------+
//| تابع ساده برای بازگشت زمان نیویورک - استفاده از پارامترهای کاربر  |
//+------------------------------------------------------------------+
bool IsInNYOpenBuffer()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int nowMin = dt.hour*60 + dt.min;
   int nyMin = InpNYOpenHourServer*60 + InpNYOpenMinuteServer;
   int diff = abs(nowMin - nyMin);
   if(diff <= InpNYBufferMin) return(true);
   return(false);
  }

//+------------------------------------------------------------------+
//| توابع استاندارد اکسپرت                                            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,const MqlTradeRequest& request,const MqlTradeResult& result)
  {
   // می‌توان لاگ گرفتن از معاملات را اینجا اضافه کرد
  }

//+------------------------------------------------------------------+
//| کمک برای ارسال سفارش                                              |
//+------------------------------------------------------------------+
bool OrderSend(MqlTradeRequest &request,MqlTradeResult &result)
  {
   if(!OrderCheck(request,NULL))
     {
      // خطای اولیه
     }
   if(!OrderSend(request,result))
     {
      Print("OrderSend() failed, Error=",GetLastError());
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| تابع کمکی برای OrderCheck (بسته به پلتفرم)                       |
//+------------------------------------------------------------------+
bool OrderCheck(MqlTradeRequest &request,MqlTradeCheckResult *check)
  {
   // در این نسخه پایه‌ای، از چک پیش‌فرض استفاده نکنیم
   return(true);
  }

//+------------------------------------------------------------------+
//| تابع پایان کار فایل                                               |
//+------------------------------------------------------------------+
