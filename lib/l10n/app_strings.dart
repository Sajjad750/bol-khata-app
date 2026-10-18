import 'app_language.dart';

/// Lightweight string catalog for Bol Khata (EN / Urdu / Roman Urdu).
class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  String _t(String en, String ur, String rom) => switch (language) {
    AppLanguage.english => en,
    AppLanguage.urdu => ur,
    AppLanguage.romanUrdu => rom,
  };

  // ---- Common ----
  String get appName => 'Bol Khata';
  String get cancel => _t('Cancel', 'منسوخ', 'Cancel');
  String get save => _t('Save', 'محفوظ', 'Save');
  String get discard => _t('Discard', 'رد کریں', 'Discard');
  String get confirm => _t('Confirm', 'تصدیق', 'Confirm');
  String get tryAgain => _t('Try again', 'دوبارہ کوشش', 'Dobara koshish');
  String get ok => _t('OK', 'ٹھیک ہے', 'OK');
  String get add => _t('Add', 'شامل', 'Add');
  String get speak => _t('Speak', 'بولیں', 'Bolein');
  String get listening => _t('Listening', 'سن رہے ہیں', 'Sun rahe hain');
  String get wait => _t('Wait…', 'انتظار…', 'Intezaar…');
  String get searchHint => _t(
    'Search name or phone',
    'نام یا نمبر تلاش کریں',
    'Naam ya number dhoondain',
  );
  String get settled => _t('Settled', 'حساب برابر', 'Hisab barabar');
  String get customerOwesYou => _t(
    'Customer owes you',
    'گاہک آپ کا مقروض ہے',
    'Gahak aap ka maqrooz hai',
  );
  String get youOweCustomer => _t(
    'You owe customer',
    'آپ گاہک کے مقروض ہیں',
    'Aap gahak ke maqrooz hain',
  );
  String get udharDiya => _t('Udhar Diya', 'ادھار دیا', 'Udhar Diya');
  String get paymentLiya => _t('Payment Liya', 'ادائیگی لی', 'Payment Liya');
  String get entrySaved =>
      _t('Entry saved', 'اندراج محفوظ ہو گیا', 'Entry save ho gaya');
  String get somethingWentWrong => _t(
    'Something went wrong. Please try again.',
    'کچھ غلط ہو گیا۔ دوبارہ کوشش کریں۔',
    'Kuch galat ho gaya. Dobara koshish karein.',
  );

  // ---- Language picker ----
  String get chooseLanguageTitle =>
      _t('Choose your language', 'اپنی زبان منتخب کریں', 'Apni zubaan chunein');
  String get chooseLanguageSubtitle => _t(
    'This sets the app text and how voice entries are written.',
    'اس سے ایپ کا متن اور آواز کا اندراج طے ہوگا۔',
    'Is se app ka text aur awaaz ka andraj set hoga.',
  );
  String get continueLabel => _t('Continue', 'آگے بڑھیں', 'Aage badhein');
  String get changeLanguage =>
      _t('Change language', 'زبان تبدیل کریں', 'Zubaan badlein');

  // ---- Auth / onboarding ----
  String get enterPinToUnlock => _t(
    'Enter PIN to unlock',
    'کھولنے کے لیے پن درج کریں',
    'Kholne ke liye PIN dalein',
  );
  String get unlockWithBiometric => _t(
    'Unlock with fingerprint / face',
    'فنگر پرنٹ / چہرے سے کھولیں',
    'Fingerprint / face se kholein',
  );
  String get phoneStepTitle => _t(
    'Verify your shop phone once for cloud backup — or add it later and start using Bol Khata now.',
    'کلاؤڈ بیک اپ کے لیے ایک بار دکان کا نمبر تصدیق کریں — یا بعد میں شامل کر کے ابھی شروع کریں۔',
    'Cloud backup ke liye ek dafa shop number verify karein — ya baad mein add karke abhi shuru karein.',
  );
  String get phoneLabel => _t('Mobile number', 'موبائل نمبر', 'Mobile number');
  String get phoneHint => _t('03XXXXXXXXX', '03XXXXXXXXX', '03XXXXXXXXX');
  String get sendOtp => _t('Send OTP', 'او ٹی پی بھیجیں', 'OTP bhejein');
  String get addNumberLater => _t(
    'Add number later',
    'نمبر بعد میں شامل کریں',
    'Number baad mein shamil karein',
  );
  String get otpStepTitle => _t(
    'Enter the OTP sent to your phone',
    'فون پر آیا او ٹی پی درج کریں',
    'Phone par aya OTP dalein',
  );
  String get verifyOtp => _t('Verify OTP', 'او ٹی پی تصدیق', 'OTP tasdeeq');
  String get pinStepTitle => _t(
    'Create a 4-digit PIN',
    '۴ ہندسوں کا پن بنائیں',
    '4 digit PIN banayein',
  );
  String get confirmPinTitle => _t(
    'Confirm your PIN',
    'اپنا پن دوبارہ درج کریں',
    'Apna PIN dobara dalein',
  );
  String get biometricTitle => _t(
    'Unlock faster with biometric?',
    'فنگر پرنٹ سے تیزی سے کھولیں؟',
    'Fingerprint se tezi se kholein?',
  );
  String get enableBiometric => _t(
    'Use fingerprint / face unlock',
    'فنگر پرنٹ / چہرہ استعمال کریں',
    'Fingerprint / face use karein',
  );
  String get finishSetup =>
      _t('Finish setup', 'سیٹ اپ مکمل کریں', 'Setup mukammal karein');
  String get skipBiometric =>
      _t('Skip for now', 'ابھی چھوڑیں', 'Abhi chhor dein');

  // ---- Home ----
  String get allCustomers => _t('All customers', 'تمام گاہک', 'Tamam gahak');
  String get noCustomersYet =>
      _t('No customers yet', 'ابھی کوئی گاہک نہیں', 'Abhi koi gahak nahi');
  String get addFirstCustomer => _t(
    'Add first customer',
    'پہلا گاہک شامل کریں',
    'Pehla gahak shamil karein',
  );
  String get addFirstCustomerHint => _t(
    'Add your first customer to start tracking udhar and payments.',
    'ادھار اور ادائیگی شروع کرنے کے لیے پہلا گاہک شامل کریں۔',
    'Udhar aur payment shuru karne ke liye pehla gahak shamil karein.',
  );
  String get owesYou => _t('Owes you', 'آپ کے مقروض', 'Aap ke maqrooz');
  String get youOwe => _t('You owe', 'آپ مقروض', 'Aap maqrooz');
  String get toCollect => _t('To collect', 'وصول کرنا ہے', 'Wasool karna hai');
  String get receivedBack => _t('Received', 'وصول ہو چکا', 'Wasool ho chuka');
  String get toCollectTitle =>
      _t('To collect', 'وصول کرنا ہے', 'Wasool karna hai');
  String get receivedTitle =>
      _t('Payments received', 'موصول ادائیگیاں', 'Mili hui payments');
  String get noOneOwesYou => _t(
    'No one owes you right now.',
    'ابھی کوئی آپ کا مقروض نہیں۔',
    'Abhi koi aap ka maqrooz nahi.',
  );
  String get noPaymentsYet => _t(
    'No payments received yet.',
    'ابھی کوئی ادائیگی نہیں ملی۔',
    'Abhi koi payment nahi mili.',
  );
  String get noPhone => _t('No phone', 'نمبر نہیں', 'Number nahi');
  String get signOut => _t('Sign out', 'سائن آؤٹ', 'Sign out');
  String get addPhoneNumber => _t(
    'Add phone number',
    'فون نمبر شامل کریں',
    'Phone number shamil karein',
  );

  // ---- Customer ----
  String get customer => _t('Customer', 'گاہک', 'Gahak');
  String get editCustomer => _t('Edit customer', 'گاہک ترمیم', 'Gahak tarmim');
  String get deleteKhata =>
      _t('Delete khata', 'کھاتہ حذف کریں', 'Khata delete karein');
  String get deleteKhataTitle => _t(
    'Delete this khata?',
    'یہ کھاتہ حذف کریں؟',
    'Yeh khata delete karein?',
  );
  String deleteKhataMessage(String name) => _t(
    'This will permanently delete $name’s khata and all entries. This cannot be undone.',
    '$name کا کھاتہ اور تمام اندراجات مستقل طور پر حذف ہو جائیں گے۔ یہ واپس نہیں ہو سکتا۔',
    '$name ka khata aur tamam entries permanent delete ho jayengi. Yeh wapas nahi ho sakta.',
  );
  String get deleteKhataConfirm => _t('Delete', 'حذف کریں', 'Delete');
  String get khataDeleted =>
      _t('Khata deleted', 'کھاتہ حذف ہو گیا', 'Khata delete ho gaya');
  String get deleteEntry =>
      _t('Delete entry', 'اندراج حذف کریں', 'Entry delete karein');
  String get deleteEntryTitle => _t(
    'Delete this entry?',
    'یہ اندراج حذف کریں؟',
    'Yeh entry delete karein?',
  );
  String get deleteEntryMessage => _t(
    'This entry will be removed from the customer’s balance. This cannot be undone.',
    'یہ اندراج گاہک کے بیلنس سے ہٹا دیا جائے گا۔ یہ واپس نہیں ہو سکتا۔',
    'Yeh entry gahak ke balance se hata di jayegi. Yeh wapas nahi ho sakta.',
  );
  String get entryDeleted =>
      _t('Entry deleted', 'اندراج حذف ہو گیا', 'Entry delete ho gayi');
  String get addChangePhoto =>
      _t('Add / change photo', 'تصویر شامل / تبدیل', 'Photo shamil / badlein');
  String get addNumber =>
      _t('Add number', 'نمبر شامل کریں', 'Number shamil karein');
  String get noKhataEntries => _t(
    'No khata entries yet.\nUse Add, Speak, or the buttons below.',
    'ابھی کوئی کھاتہ اندراج نہیں۔\nشامل کریں، بولیں، یا نیچے والے بٹن استعمال کریں۔',
    'Abhi koi khata entry nahi.\nAdd karein, Bolein, ya neeche buttons use karein.',
  );
  String get addProductsDetails => _t(
    'Add products / details',
    'سامان / تفصیل شامل کریں',
    'Samaan / tafseel shamil karein',
  );
  String get holdToSpeakFor => _t(
    'Hold to speak',
    'بولنے کے لیے دبائے رکھیں',
    'Bolne ke liye dabaye rakhein',
  );
  String holdToSpeakNamed(String name) => _t(
    'Hold to speak for $name',
    '$name کے لیے بولنے کو دبائے رکھیں',
    '$name ke liye bolne ko dabaye rakhein',
  );
  String get udharDiyaShort => _t('Udhar diya', 'ادھار دیا', 'Udhar diya');
  String get paymentLiyaShort =>
      _t('Payment liya', 'ادائیگی لی', 'Payment liya');

  // ---- Voice / confirm ----
  String get confirmEntry =>
      _t('Confirm entry', 'اندراج تصدیق', 'Entry ki tasdeeq');
  String get entryDetail =>
      _t('Entry detail', 'اندراج کی تفصیل', 'Entry ki tafseel');
  String get addEntry =>
      _t('Add entry', 'اندراج شامل کریں', 'Entry shamil karein');
  String get items => _t('Items', 'اشیا', 'Cheezein');
  String get addItem => _t('Add item', 'آئٹم شامل', 'Item shamil');
  String get editItem => _t('Edit item', 'آئٹم ترمیم', 'Item tarmim');
  String get itemName => _t('Item name', 'آئٹم کا نام', 'Item ka naam');
  String get quantity => _t('Quantity', 'مقدار', 'Miqdar');
  String get unit =>
      _t('Unit (kg, dozen…)', 'اکائی (کلو، درجن…)', 'Unit (kg, dozen…)');
  String get priceRs => _t('Price (Rs)', 'قیمت (روپے)', 'Qeemat (Rs)');
  String get amountAndType =>
      _t('Amount & type', 'رقم اور قسم', 'Raqam aur qism');
  String get noteOptional =>
      _t('Note (optional)', 'نوٹ (اختیاری)', 'Note (ikhtiyari)');
  String get tapToEnterAmount => _t(
    'Tap to enter amount',
    'رقم درج کرنے کے لیے تھپتھپائیں',
    'Raqam dalne ke liye dabayein',
  );
  String get tapToEdit =>
      _t('Tap to edit', 'ترمیم کے لیے تھپتھپائیں', 'Tarmim ke liye dabayein');
  String get savingToThisCustomer => _t(
    "Saving to this customer's khata",
    'اس گاہک کے کھاتے میں محفوظ ہوگا',
    'Is gahak ke khate mein save hoga',
  );
  String get voiceEntryFailed =>
      _t('Voice entry failed', 'آواز اندراج ناکام', 'Awaz entry nakam');
  String get enterManually =>
      _t('Enter manually', 'خود درج کریں', 'Khud darj karein');
  String get noItemsHintManual => _t(
    'Add products for this khata (optional), then set the total.',
    'اس کھاتے کے لیے سامان شامل کریں (اختیاری)، پھر کل رقم رکھیں۔',
    'Is khate ke liye samaan shamil karein (optional), phir total rakhein.',
  );
  String get noItemsHintVoice => _t(
    'No items parsed — plain amount entry.',
    'کوئی آئٹم نہیں ملا — صرف رقم کا اندراج۔',
    'Koi item nahi mila — sirf raqam ka andraj.',
  );

  // ---- Amount sheet ----
  String get enterAnAmount =>
      _t('Enter an amount', 'رقم درج کریں', 'Raqam dalein');
  String get noteOptionalHint => _t(
    'Note (optional) — e.g. rice and oil',
    'نوٹ (اختیاری) — مثلاً چاول اور تیل',
    'Note (optional) — maslan chawal aur oil',
  );
  String get saving => _t('Saving…', 'محفوظ ہو رہا ہے…', 'Save ho raha hai…');
}
