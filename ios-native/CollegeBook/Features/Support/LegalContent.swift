// Generated from lib/features/support/legal_content.dart (the native
// LegalContent.java): keep the wording identical.

let supportPhone = "8500001406"
let supportPhoneDisplay = "+91 85000 01406"

enum LegalDoc: String, Hashable {
  case privacy, terms

  var title: String { self == .privacy ? "Privacy Policy" : "Terms & Conditions" }

  var intro: String {
    self == .privacy
      ? "Your trust matters to us. This policy explains what information CollegeBook collects, why we need it, who it is shared with and the choices you have."
      : "These terms apply whenever you use the CollegeBook app. Please read them carefully – by creating an account or using the app, you agree to them."
  }

  var sections: [(String, String)] { self == .privacy ? privacySections : termsSections }
}

private let privacySections: [(String, String)] = [
  ("Who we are", "CollegeBook is a NEET PG college-guidance app operated by MiniBrain (\"we\", \"us\"). This policy covers the CollegeBook app and the services offered through it."),
  ("Information we collect", "• Account details – your mobile number (used for OTP login) and your name.\n• What you do in the app – choice lists and the choices in them, favourite mentors, searches and filters, and details of mentor calls such as date, duration and mentor.\n• Payments – wallet top-ups and transaction records. Card, UPI and bank details are entered on Razorpay's secure checkout; CollegeBook never sees or stores them.\n• Device information – device model, operating system version, app version, a notification token, and anonymous usage and crash data.\n• Camera and microphone – used only while you are on a video call that you start or accept. We do not access them at any other time."),
  ("How we use your information", "• To create your account and keep you signed in.\n• To show colleges, cutoffs, fees and matches relevant to you.\n• To save your choice lists and favourites across sessions.\n• To connect and bill mentor video calls.\n• To process wallet payments.\n• To send counselling deadlines, call alerts and important updates (you can turn notifications off at any time).\n• To answer support requests, prevent fraud and misuse, and improve the app."),
  ("Sharing & disclosure", "We do not sell your personal information. We share it only when needed to run the app:\n• With the mentor you call – only what is needed for the call, such as your name.\n• With service providers who work for us – Razorpay (payments), Google Firebase (notifications and analytics), our video-calling provider and our cloud hosting. They may use the data only to provide their service to us.\n• When the law requires it, or to protect the rights and safety of our users.\n• If CollegeBook is merged or acquired, in which case this policy continues to apply."),
  ("Data security", "All data travels over encrypted (HTTPS) connections. Access to personal data is limited to people who need it to run the service, and logins use one-time passwords and secure tokens. No system is completely secure, but we work hard to protect your information and will act promptly if a problem occurs."),
  ("Retention & deletion", "We keep your information while your account is active. You can delete your account at any time from Delete Account in the app's side menu, or ask us through Contact Us; we will delete or anonymise your data within 30 days, except records we must keep by law (for example, payment records for tax purposes)."),
  ("Your rights & choices", "• See or correct the information linked to your account.\n• Ask for your account and data to be deleted.\n• Turn notifications off in the app or in your phone's settings.\n• Withdraw camera or microphone permission in your phone's settings at any time (video calls will not work without them)."),
  ("Children", "CollegeBook is meant for medical graduates and postgraduate aspirants. It is not intended for anyone under 18, and we do not knowingly collect their information."),
  ("Third-party links", "The app may link to official counselling portals, college websites and video platforms. Their own privacy policies apply once you leave CollegeBook."),
  ("Changes to this policy", "We may update this policy as the app grows. The date at the top shows the latest version, and we will let you know in the app about any significant change."),
  ("Contact", "Questions or requests about your privacy? Call or WhatsApp us on +91 85000 01406, or use Contact Us in the app."),
]

private let termsSections: [(String, String)] = [
  ("Acceptance of terms", "By creating an account or using CollegeBook you agree to these Terms and to our Privacy Policy. If you do not agree, please do not use the app."),
  ("Eligibility & your account", "You must be at least 18 years old. Keep your registered mobile number and OTPs private – you are responsible for activity on your account. Give accurate information and keep one account per person."),
  ("Our services", "CollegeBook provides information and guidance for NEET PG counselling: college details, previous cutoffs and closing ranks, rank-wise matching, fee details, counselling choice lists, 1-to-1 video calls with mentors, videos and webinars, community discussions and premium packages. Some features are free and some are paid."),
  ("Information & accuracy", "Cutoffs, seats, fees and other data are compiled from official and public sources such as MCC, state counselling authorities, NBEMS and college notices. We work to keep it accurate, but it may contain errors or be out of date, and matches and predictions are estimates based on past data. Always confirm on the official counselling portals before you lock your choices."),
  ("No guarantee of admission", "CollegeBook is an independent platform. We are not affiliated with MCC, NBEMS, NMC, any state counselling authority or any college, and we do not allot seats. Using the app does not guarantee any seat, college, course or result – all counselling decisions are yours."),
  ("Mentor video calls", "Mentors are practising PGs and faculty who share their own experience. Their views are personal and are not official, medical or legal advice. The call fee and duration are shown before you start, and the fee is paid from your wallet. Please be respectful, and do not record or share a call without the other person's consent."),
  ("Wallet, payments & premium", "Prices are in Indian Rupees and are shown before you pay. Payments are processed securely by Razorpay. Wallet balance can be used only for services inside CollegeBook and cannot be transferred to another account."),
  ("Acceptable use", "Do not misuse the app: no false information, harassment, abusive or misleading content, spam, attempts to break or overload our systems, automated scraping, or copying and republishing CollegeBook data. Accounts that break these rules may be suspended."),
  ("Community content", "You are responsible for what you post. By posting, you allow CollegeBook to display it in the app. We may remove content that breaks these Terms or the law."),
  ("Intellectual property", "The app's design, software, compiled data, analysis and content belong to MiniBrain. You may use them for your own counselling only – not for resale, coaching material or building a competing product."),
  ("Suspension & termination", "You may stop using CollegeBook and delete your account from the app's side menu at any time. We may suspend or close accounts that misuse the service or break these Terms."),
  ("Limitation of liability", "CollegeBook is provided \"as is\". To the extent the law allows, we are not liable for decisions made using information in the app, for missed counselling deadlines, or for indirect losses. Our total liability is limited to the amount you paid us in the three months before the claim."),
  ("Changes to these terms", "We may update these Terms from time to time. Continuing to use the app after a change means you accept the updated Terms."),
  ("Governing law", "These Terms are governed by the laws of India, and disputes are subject to the jurisdiction of the competent courts in India."),
  ("Contact", "Questions about these Terms? Call or WhatsApp us on +91 85000 01406."),
]
