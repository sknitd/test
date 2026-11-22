// Offline "demo" provider: deterministic stand-ins for every agent so the whole
// multi-agent pipeline runs (and looks real) without any API key. When a real
// provider is configured, these are also used as a safety net if a call fails.

import { normalizeTokens, contrast } from "./site.js";

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const hash = (s) => [...String(s)].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);
const pick = (arr, seed) => arr[seed % arr.length];
const cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);

// ------------------------------------------------------------------ profiles

const PROFILES = {
  restaurant: {
    kw: ["restaurant", "cafe", "café", "coffee", "bistro", "bakery", "pizza", "pizzeria", "sushi", "bar", "food", "kitchen", "diner", "brunch", "trattoria", "tacos", "ramen", "eatery", "patisserie"],
    noun: "restaurant",
    names: ["Olive & Ember", "The Copper Spoon", "Saffron House", "Little Fig", "Harbor Table"],
    emoji: "🍽️",
    fonts: ["Playfair Display", "Lato"],
    palettes: [
      { primary: "#b4462b", secondary: "#2b1d16", accent: "#e0a43b", bg: "#fffaf3", surface: "#f6ece0", text: "#2b1d16", muted: "#6b5a4e", onPrimary: "#ffffff" },
      { primary: "#2f5d50", secondary: "#1c2421", accent: "#d98e3a", bg: "#fbf8f2", surface: "#eef0e8", text: "#1c2421", muted: "#55615b", onPrimary: "#ffffff" },
    ],
    sections: ["nav", "hero", "about", "menu", "gallery", "testimonials", "contact", "footer"],
    hero: ["Seasonal food, made with heart", "A neighbourhood table worth crossing town for"],
    sub: "Fresh, local ingredients cooked simply and served with warmth{city}. Come hungry, leave happy.",
    cta: "Book a table",
    features: [["🌿", "Locally sourced", "We work with farms within 50 miles and change the menu with the seasons."], ["🔥", "Wood-fired kitchen", "Our open hearth gives every dish a gentle, smoky depth."], ["🍷", "Curated wine list", "Small producers, natural wines and plenty by the glass."]],
    menu: [["Burrata & heirloom tomatoes", "Basil oil, sourdough crumb", "$14"], ["Charred octopus", "Smoked paprika, lemon, potato", "$18"], ["Wild mushroom risotto", "Aged parmesan, thyme", "$22"], ["Hanger steak frites", "Peppercorn sauce, herb salad", "$29"], ["Catch of the day", "Brown butter, capers, greens", "$27"], ["Olive-oil cake", "Citrus curd, crème fraîche", "$10"]],
    gallery: ["🍝 Handmade pasta", "🥖 Morning bread", "🍷 The wine bar", "🔥 Open kitchen", "🌿 Garden terrace", "🍰 Dessert counter"],
    testimonials: [["Every dish felt personal. The risotto alone is worth the trip.", "Maya R.", "Local guide"], ["Warm service, beautiful room, and the best steak frites in town.", "Daniel K.", "Regular since 2019"], ["Our go-to for birthdays. They make every visit feel special.", "Priya S.", "Food blogger"]],
    contactTitle: "Reserve your table",
  },
  saas: {
    kw: ["saas", "app", "software", "platform", "startup", "ai", "tool", "api", "dashboard", "crm", "analytics", "automation", "fintech", "productivity", "b2b", "devtool"],
    noun: "platform",
    names: ["Nimbus", "Flowbase", "Lumen AI", "Orbitly", "Taskwise"],
    emoji: "🚀",
    fonts: ["Plus Jakarta Sans", "Inter"],
    palettes: [
      { primary: "#5b4cf0", secondary: "#0f1222", accent: "#22d3ee", bg: "#ffffff", surface: "#f3f4fb", text: "#0f1222", muted: "#545b72", onPrimary: "#ffffff" },
      { primary: "#0e7c66", secondary: "#071a16", accent: "#7cf2c8", bg: "#ffffff", surface: "#eff7f4", text: "#0c1a17", muted: "#4d625c", onPrimary: "#ffffff" },
    ],
    sections: ["nav", "hero", "stats", "features", "services", "pricing", "testimonials", "faq", "cta", "footer"],
    hero: ["Do your best work, without the busywork", "The faster way for modern teams to ship"],
    sub: "{name} brings your workflows, data and team into one place — so you spend less time managing work and more time doing it.",
    cta: "Start free trial",
    features: [["⚡", "Lightning fast", "Built on a modern stack so every action feels instant, even at scale."], ["🔒", "Secure by default", "SSO, audit logs and encryption at rest come standard on every plan."], ["🤝", "Built for teams", "Real-time collaboration, comments and mentions keep everyone in sync."], ["📊", "Insightful analytics", "Dashboards that turn activity into decisions, no spreadsheet needed."], ["🔌", "100+ integrations", "Connect the tools you already use in a couple of clicks."], ["🤖", "Smart automation", "Automate repetitive steps with rules anyone on the team can set up."]],
    steps: [["Connect your tools", "Import data and invite your team in minutes."], ["Automate the routine", "Pick a template or build your own workflows."], ["Ship with confidence", "Track progress and results in real time."]],
    stats: [["12k+", "teams onboard"], ["99.99%", "uptime"], ["4.9/5", "average rating"], ["38%", "time saved"]],
    pricing: [["Starter", "$0", "For individuals getting started", ["Up to 3 projects", "Basic automations", "Community support"]], ["Pro", "$19", "For growing teams", ["Unlimited projects", "Advanced automations", "Analytics dashboards", "Priority support"]], ["Business", "$49", "For organisations at scale", ["SSO & audit logs", "Custom roles", "Dedicated success manager"]]],
    testimonials: [["We replaced four tools with {name} and our weekly planning time halved.", "Elena M.", "Head of Ops, Brightline"], ["Setup took an afternoon. The automations paid for themselves in a week.", "Marcus T.", "CTO, Fieldnote"], ["Finally a product our whole team actually enjoys using.", "Aisha B.", "Product Lead, Northwind"]],
    faq: [["Is there a free plan?", "Yes — the Starter plan is free forever for individuals."], ["Can I cancel anytime?", "Absolutely. Plans are month-to-month and you can cancel in one click."], ["Is my data secure?", "Data is encrypted in transit and at rest, and we offer SSO on Business plans."], ["Do you offer discounts for non-profits?", "Yes, verified non-profits and schools get 50% off any paid plan."]],
  },
  portfolio: {
    kw: ["portfolio", "photographer", "photography", "designer", "artist", "illustrator", "personal", "resume", "cv", "freelance", "freelancer", "creative", "architect", "writer", "musician"],
    noun: "studio",
    names: ["Alex Morgan", "Studio Noor", "Jamie Lee", "Ren Ito"],
    emoji: "✦",
    fonts: ["DM Serif Display", "DM Sans"],
    palettes: [
      { primary: "#111111", secondary: "#111111", accent: "#ff5a36", bg: "#f7f5f0", surface: "#ebe7de", text: "#141414", muted: "#5c5850", onPrimary: "#ffffff" },
      { primary: "#e8ff59", secondary: "#0b0b0c", accent: "#8b5cf6", bg: "#0e0e10", surface: "#1a1a1e", text: "#f2f2f2", muted: "#a5a5ad", onPrimary: "#0b0b0c" },
    ],
    sections: ["nav", "hero", "gallery", "about", "services", "testimonials", "contact", "footer"],
    hero: ["Thoughtful work for curious brands", "Crafting images and identities that last"],
    sub: "I'm {name}, an independent {role}{city}. I help people tell honest stories through considered, beautiful work.",
    cta: "See selected work",
    features: [["🎯", "Brand identity", "Logos, systems and guidelines built to grow with you."], ["📸", "Art direction", "Shoots and campaigns with a clear, consistent point of view."], ["🖥️", "Digital design", "Websites and products that feel as good as they look."]],
    gallery: ["🌅 Coastal Light — editorial", "🏛️ Atelier — brand identity", "🌿 Verde — packaging", "🎞️ Night Shift — campaign", "🪴 Habitat — interiors", "🎨 Bloom — illustration"],
    testimonials: [["Sharp eye, calm process, and work that made our launch.", "Hannah W.", "Founder, Kin Coffee"], ["Exceeded the brief in every way. A true collaborator.", "Omar F.", "Marketing Director, Atlas"], ["Thoughtful, fast and endlessly creative.", "Lucía P.", "Editor, Field Notes"]],
    contactTitle: "Let's make something together",
  },
  agency: {
    kw: ["agency", "design studio", "creative studio", "marketing", "consultancy", "consulting", "firm", "branding", "seo", "advertising", "digital agency"],
    noun: "agency",
    names: ["Northbeam", "Brightside Co.", "Parallel", "Kindred Studio"],
    emoji: "◆",
    fonts: ["Space Grotesk", "Inter"],
    palettes: [{ primary: "#ff4d2e", secondary: "#14110f", accent: "#ffd23f", bg: "#fffdf9", surface: "#f4efe8", text: "#14110f", muted: "#5d564f", onPrimary: "#ffffff" }],
    sections: ["nav", "hero", "services", "stats", "gallery", "testimonials", "team", "cta", "footer"],
    hero: ["We build brands people remember", "Strategy, design and growth — under one roof"],
    sub: "{name} is an independent {noun}{city} partnering with ambitious companies to launch, grow and stand out.",
    cta: "Start a project",
    features: [["🧭", "Strategy", "Research, positioning and messaging that give your brand direction."], ["🎨", "Brand & design", "Identity systems, websites and campaigns crafted with care."], ["📈", "Growth marketing", "Performance campaigns, SEO and content that compound over time."], ["🛠️", "Product", "Design and build digital products customers love to use."]],
    stats: [["140+", "brands launched"], ["12", "industry awards"], ["3.2x", "average ROI"], ["9 yrs", "in business"]],
    gallery: ["☕ Kin Coffee — rebrand", "🚲 Velo — launch campaign", "🏦 Ledger — product design", "🌱 Grove — e-commerce", "🎧 Wave — app", "🏔️ Summit — identity"],
    testimonials: [["They understood our business faster than any agency we've worked with.", "Sara L.", "CEO, Velo"], ["Our new brand doubled inbound leads within a quarter.", "Tom H.", "Founder, Ledger"], ["Creative, strategic and a joy to work with.", "Nina G.", "CMO, Grove"]],
    team: [["Jordan Blake", "Founder & Strategy"], ["Mei Chen", "Design Director"], ["Sam Okafor", "Head of Growth"], ["Ava Novak", "Lead Developer"]],
  },
  fitness: {
    kw: ["gym", "fitness", "yoga", "pilates", "trainer", "training", "crossfit", "wellness", "spa", "boxing", "studio fitness", "workout", "martial"],
    noun: "studio",
    names: ["Pulse Studio", "Ironwood Gym", "Flow Yoga", "Peak Athletics"],
    emoji: "💪",
    fonts: ["Oswald", "Inter"],
    palettes: [
      { primary: "#e11d48", secondary: "#0b0b0f", accent: "#facc15", bg: "#0f0f13", surface: "#1b1b22", text: "#f5f5f7", muted: "#b2b2bd", onPrimary: "#ffffff" },
      { primary: "#3a7d5c", secondary: "#1d2a24", accent: "#e9b872", bg: "#f8f6f1", surface: "#ecebe3", text: "#1d2a24", muted: "#57635c", onPrimary: "#ffffff" },
    ],
    sections: ["nav", "hero", "features", "services", "pricing", "team", "testimonials", "contact", "footer"],
    hero: ["Stronger every single day", "Train with purpose. Feel the difference."],
    sub: "Coaching, classes and a community that keeps you showing up{city}. Your first class is on us.",
    cta: "Claim free class",
    features: [["🏋️", "Expert coaching", "Certified coaches who tailor every session to your goals."], ["🗓️", "60+ weekly classes", "Strength, HIIT, mobility and yoga from 6am to 9pm."], ["🤝", "Real community", "Train alongside people who cheer you on."]],
    steps: [["Book your free class", "Pick any session that suits your schedule."], ["Meet your coach", "We'll learn your goals and build your plan."], ["Track your progress", "Monthly check-ins keep you moving forward."]],
    pricing: [["Drop-in", "$25", "Single class", ["Any class", "Towel & locker"]], ["Unlimited", "$129", "Per month", ["Unlimited classes", "Monthly check-in", "Member events"]], ["Personal", "$249", "Per month", ["8 PT sessions", "Custom programme", "Nutrition guide"]]],
    team: [["Kai Reynolds", "Head Coach"], ["Sofia Marin", "Yoga & Mobility"], ["Leo Grant", "Strength & Conditioning"]],
    testimonials: [["I've never stuck with a gym this long. The coaches genuinely care.", "Chris D.", "Member, 2 years"], ["Down 12kg and stronger than ever.", "Fatima A.", "Member"], ["The classes are tough, fun and never the same twice.", "Ben W.", "Member"]],
    contactTitle: "Book your free class",
  },
  shop: {
    kw: ["shop", "store", "ecommerce", "e-commerce", "boutique", "clothing", "fashion", "jewelry", "jewellery", "candles", "skincare", "sell", "products", "merch", "handmade"],
    noun: "shop",
    names: ["Maison Verre", "Kindred Goods", "Field & Thread", "Lune"],
    emoji: "🛍️",
    fonts: ["Fraunces", "Manrope"],
    palettes: [{ primary: "#3d5a40", secondary: "#1f2620", accent: "#d9a066", bg: "#fbf9f5", surface: "#f0ece4", text: "#1f2620", muted: "#5b625a", onPrimary: "#ffffff" }],
    sections: ["nav", "hero", "products", "features", "about", "testimonials", "cta", "footer"],
    hero: ["Thoughtfully made, made to last", "Everyday goods with a story"],
    sub: "Small-batch pieces crafted by independent makers{city}. Free shipping on orders over $75.",
    cta: "Shop the collection",
    features: [["🌍", "Sustainably sourced", "Natural materials from suppliers we know by name."], ["🚚", "Free shipping", "On every order over $75, with easy 30-day returns."], ["✋", "Handmade", "Each piece is finished by hand in small batches."]],
    menu: [["Linen throw", "Stone-washed, oat", "$89"], ["Ceramic mug set", "Set of two, speckled glaze", "$42"], ["Beeswax candle", "Cedar & fig, 40h burn", "$28"], ["Wool blanket", "Merino, forest green", "$149"], ["Oak serving board", "Hand-oiled, large", "$64"], ["Cotton tote", "Organic canvas", "$24"]],
    testimonials: [["Beautiful quality and the packaging felt like a gift.", "Grace T.", "Verified buyer"], ["My favourite shop for presents — never disappoints.", "Imran K.", "Verified buyer"], ["The blanket is even softer in person.", "Zoe P.", "Verified buyer"]],
  },
  event: {
    kw: ["event", "conference", "wedding", "festival", "meetup", "summit", "concert", "party", "hackathon", "expo", "gala", "retreat"],
    noun: "event",
    names: ["Horizon Summit", "Future Forward", "Lumen Fest", "Make & Meet"],
    emoji: "🎟️",
    fonts: ["Sora", "Inter"],
    palettes: [{ primary: "#7c3aed", secondary: "#120b24", accent: "#f472b6", bg: "#0f0a1f", surface: "#1c1533", text: "#f4f1ff", muted: "#b9b2d6", onPrimary: "#ffffff" }],
    sections: ["nav", "hero", "about", "stats", "services", "team", "pricing", "faq", "contact", "footer"],
    hero: ["Two days that change how you think", "Where ideas meet the people who build them"],
    sub: "Join speakers, makers and leaders{city} for talks, workshops and conversations that matter.",
    cta: "Get your ticket",
    steps: [["Day 1 — Keynotes", "Opening keynote, panels and the evening social."], ["Day 2 — Workshops", "Hands-on sessions led by practitioners."], ["After-party", "Live music, food trucks and great company."]],
    stats: [["40+", "speakers"], ["2,000", "attendees"], ["24", "workshops"], ["2", "unforgettable days"]],
    team: [["Dr. Amara Obi", "Keynote · Future of Work"], ["Lucas Ferreira", "Design Systems"], ["Hana Sato", "Climate Tech"], ["Ravi Patel", "AI & Society"]],
    pricing: [["Standard", "$199", "Full two-day access", ["All talks", "Lunch both days", "After-party"]], ["VIP", "$449", "The full experience", ["Front-row seating", "Speaker dinner", "Workshop priority"]], ["Student", "$79", "With valid ID", ["All talks", "Lunch both days"]]],
    faq: [["Where is the venue?", "Full venue details and directions are sent with your ticket."], ["Can I get a refund?", "Tickets are refundable up to 14 days before the event."], ["Will talks be recorded?", "Yes, ticket holders get access to all recordings."], ["Is there a code of conduct?", "Yes — we're committed to a safe, welcoming event for everyone."]],
    contactTitle: "Questions? Get in touch",
  },
  nonprofit: {
    kw: ["nonprofit", "non-profit", "charity", "foundation", "volunteer", "donate", "ngo", "community", "shelter", "rescue", "cause"],
    noun: "organisation",
    names: ["Open Hands", "Bright Paths", "River Commons", "Hopewell"],
    emoji: "💛",
    fonts: ["Merriweather", "Source Sans 3"],
    palettes: [{ primary: "#0f766e", secondary: "#10302d", accent: "#f59e0b", bg: "#fdfcf8", surface: "#eef5f3", text: "#10302d", muted: "#4f625f", onPrimary: "#ffffff" }],
    sections: ["nav", "hero", "about", "stats", "services", "testimonials", "cta", "contact", "footer"],
    hero: ["Together, we can do more good", "Small acts, lasting change"],
    sub: "{name} connects people who care with the communities that need them most{city}.",
    cta: "Donate today",
    stats: [["25k", "meals served"], ["1,200", "volunteers"], ["48", "partner groups"], ["92%", "goes to programs"]],
    steps: [["Donate", "Every gift goes straight to our programs."], ["Volunteer", "Give a few hours and change someone's week."], ["Spread the word", "Share our story with friends and family."]],
    testimonials: [["When we needed help, they were there within a day.", "Rosa M.", "Community member"], ["Volunteering here is the highlight of my week.", "James O.", "Volunteer"], ["Transparent, effective, and deeply kind.", "Linh T.", "Monthly donor"]],
  },
  clinic: {
    kw: ["clinic", "dental", "dentist", "doctor", "medical", "health", "therapy", "therapist", "vet", "veterinary", "hospital", "physio", "physiotherapy", "chiropractor", "counselling"],
    noun: "clinic",
    names: ["Clearview Clinic", "Bright Smile Dental", "Willow Health", "Harbor Physio"],
    emoji: "🩺",
    fonts: ["Nunito Sans", "Nunito Sans"],
    palettes: [{ primary: "#0b6bcb", secondary: "#0b2540", accent: "#2dd4bf", bg: "#ffffff", surface: "#eef5fc", text: "#0b2540", muted: "#4a5f75", onPrimary: "#ffffff" }],
    sections: ["nav", "hero", "services", "about", "team", "testimonials", "faq", "contact", "footer"],
    hero: ["Gentle, expert care for the whole family", "Your health, in caring hands"],
    sub: "Modern treatment, same-week appointments and a team that listens{city}.",
    cta: "Book an appointment",
    features: [["🦷", "General care", "Check-ups, cleans and preventive care for all ages."], ["✨", "Cosmetic treatments", "Whitening, veneers and aligners with natural results."], ["🚑", "Same-day emergencies", "Urgent appointments when you need them most."], ["👶", "Family friendly", "Calm, patient care for kids and nervous patients."]],
    team: [["Dr. Sarah Lin", "Lead Practitioner"], ["Dr. Ahmed Khan", "Specialist"], ["Emily Rose", "Patient Coordinator"]],
    testimonials: [["The most relaxed I've ever felt at an appointment.", "Hannah J.", "Patient"], ["Clear explanations and no pressure. Highly recommend.", "Mark P.", "Patient"], ["They squeezed me in the same day. Lifesavers.", "Olivia N.", "Patient"]],
    faq: [["Do you accept insurance?", "We work with most major insurers and offer payment plans."], ["How do I book?", "Book online, call us, or use the form below."], ["Are you accepting new patients?", "Yes — new patients are always welcome."], ["What are your hours?", "Mon–Fri 8am–7pm, Sat 9am–2pm."]],
    contactTitle: "Book an appointment",
  },
  education: {
    kw: ["school", "course", "academy", "tutor", "tutoring", "learning", "university", "bootcamp", "class", "lessons", "teach", "kindergarten", "language"],
    noun: "academy",
    names: ["Brightpath Academy", "Learnly", "Northstar School", "Cedar Learning"],
    emoji: "🎓",
    fonts: ["Lexend", "Inter"],
    palettes: [{ primary: "#2563eb", secondary: "#0f1d3a", accent: "#f97316", bg: "#ffffff", surface: "#f1f5ff", text: "#0f1d3a", muted: "#4d5b78", onPrimary: "#ffffff" }],
    sections: ["nav", "hero", "features", "services", "stats", "team", "testimonials", "pricing", "faq", "footer"],
    hero: ["Learn skills that open doors", "Learning that actually sticks"],
    sub: "Expert-led courses, small cohorts and real projects{city} — so you finish confident, not just certified.",
    cta: "Explore courses",
    features: [["👩‍🏫", "Expert instructors", "Learn from practitioners with years of real-world experience."], ["🧑‍🤝‍🧑", "Small cohorts", "Max 20 learners per class so nobody gets left behind."], ["🛠️", "Project-based", "Build a portfolio of real work as you learn."]],
    steps: [["Choose a course", "Browse programs by goal and level."], ["Learn by doing", "Live classes, mentoring and weekly projects."], ["Get results", "Graduate with a portfolio and career support."]],
    stats: [["8,500+", "graduates"], ["94%", "completion rate"], ["4.8/5", "learner rating"], ["120+", "hiring partners"]],
    team: [["Prof. Ana Ruiz", "Program Director"], ["David Kim", "Lead Instructor"], ["Grace Mensah", "Career Coach"]],
    pricing: [["Self-paced", "$29", "Per month", ["All recorded lessons", "Community access"]], ["Cohort", "$490", "Per course", ["Live classes", "Mentor feedback", "Certificate"]], ["Career track", "$1,900", "6 months", ["Everything in Cohort", "1:1 coaching", "Job guarantee"]]],
    testimonials: [["The projects got me my first job offer.", "Tariq H.", "Graduate"], ["Instructors who genuinely care about your progress.", "Julia S.", "Graduate"], ["Worth every minute. I've recommended it to all my friends.", "Ken W.", "Learner"]],
    faq: [["Do I need experience?", "No — beginner courses start from zero."], ["How long are courses?", "Most run 6–12 weeks, a few hours per week."], ["Is there financial aid?", "Yes, scholarships and payment plans are available."], ["Do I get a certificate?", "Every completed course includes a verified certificate."]],
  },
  travel: {
    kw: ["hotel", "travel", "resort", "tour", "tours", "villa", "bnb", "b&b", "hostel", "adventure", "safari", "cabin", "retreat", "lodge", "guesthouse"],
    noun: "retreat",
    names: ["Azure Bay Resort", "Pine Hollow Lodge", "Casa Sol", "Wanderlight Tours"],
    emoji: "🌴",
    fonts: ["Cormorant Garamond", "Jost"],
    palettes: [{ primary: "#0e7490", secondary: "#0c2a33", accent: "#f2b880", bg: "#fcfbf8", surface: "#eef5f6", text: "#0c2a33", muted: "#4b636a", onPrimary: "#ffffff" }],
    sections: ["nav", "hero", "about", "features", "gallery", "pricing", "testimonials", "contact", "footer"],
    hero: ["Slow down. Breathe. Stay a while.", "Your escape starts here"],
    sub: "Light-filled rooms, unhurried days and unforgettable views{city}.",
    cta: "Check availability",
    features: [["🌊", "Ocean views", "Every room opens to the water and the sunrise."], ["🧖", "Spa & wellness", "Treatments inspired by local botanicals."], ["🍳", "Breakfast included", "Fresh, local and served until 11am."]],
    gallery: ["🌅 Sunrise deck", "🛏️ Garden suite", "🏊 Infinity pool", "🍹 Beach bar", "🌿 Spa garden", "⛵ Bay excursions"],
    pricing: [["Garden Room", "$189", "Per night", ["Queen bed", "Garden view", "Breakfast"]], ["Ocean Suite", "$289", "Per night", ["King bed", "Private balcony", "Breakfast & spa credit"]], ["Villa", "$520", "Per night", ["2 bedrooms", "Private pool", "Butler service"]]],
    testimonials: [["The most restful week we've had in years.", "Claire & Tom", "Stayed in June"], ["Staff remembered our names on day one.", "Andre L.", "Stayed in March"], ["Views, food and service — all perfect.", "Mina K.", "Stayed in May"]],
    contactTitle: "Plan your stay",
  },
  realestate: {
    kw: ["real estate", "realtor", "realty", "property", "properties", "homes", "apartments", "estate agent", "mortgage", "listings"],
    noun: "agency",
    names: ["Keystone Realty", "Haven Homes", "Urban Nest", "Cornerstone Property"],
    emoji: "🏡",
    fonts: ["Libre Baskerville", "Inter"],
    palettes: [{ primary: "#1e3a5f", secondary: "#0e1b2c", accent: "#c8a165", bg: "#ffffff", surface: "#f3f1ec", text: "#0e1b2c", muted: "#53606e", onPrimary: "#ffffff" }],
    sections: ["nav", "hero", "products", "services", "stats", "team", "testimonials", "contact", "footer"],
    hero: ["Find the place you'll love coming home to", "Local experts. Remarkable homes."],
    sub: "Buying, selling or renting{city} — {name} makes every move simpler.",
    cta: "Browse listings",
    menu: [["Modern townhouse", "3 bed · 2 bath · 1,850 sq ft", "$685,000"], ["Garden apartment", "2 bed · 1 bath · 960 sq ft", "$2,400/mo"], ["Family home", "4 bed · 3 bath · 2,600 sq ft", "$920,000"], ["City loft", "1 bed · 1 bath · 780 sq ft", "$449,000"], ["Lakeside cottage", "3 bed · 2 bath · 1,400 sq ft", "$610,000"], ["Penthouse", "3 bed · 3 bath · 2,100 sq ft", "$1,450,000"]],
    steps: [["Free valuation", "Know what your home is worth today."], ["Expert marketing", "Professional photos, tours and listings."], ["Smooth closing", "We handle the paperwork and negotiation."]],
    stats: [["$480M", "in sales"], ["1,100+", "homes sold"], ["21 days", "average time to sell"], ["4.9★", "client rating"]],
    team: [["Rachel Adams", "Principal Broker"], ["Luis Moreno", "Buyer's Agent"], ["Priya Nair", "Listing Specialist"]],
    testimonials: [["Sold above asking in nine days. Incredible team.", "The Harris family", "Sellers"], ["They found us a home we didn't know we could afford.", "Jen & Mo", "First-time buyers"], ["Honest advice, zero pressure.", "Victor S.", "Buyer"]],
  },
};

const GENERIC = {
  kw: [],
  noun: "business",
  names: ["Brightwave", "Summit & Co.", "Evergreen", "Northlight"],
  emoji: "✳️",
  fonts: ["Poppins", "Inter"],
  palettes: [{ primary: "#4f46e5", secondary: "#111827", accent: "#f59e0b", bg: "#ffffff", surface: "#f4f5fb", text: "#111827", muted: "#545c6c", onPrimary: "#ffffff" }],
  sections: ["nav", "hero", "features", "about", "services", "testimonials", "faq", "contact", "footer"],
  hero: ["Quality you can count on", "Built around what matters to you"],
  sub: "{name} delivers thoughtful, reliable service{city} — from the first hello to long after the job is done.",
  cta: "Get started",
  features: [["⭐", "Proven quality", "Years of experience and hundreds of happy customers."], ["⏱️", "Fast turnaround", "Clear timelines, and we stick to them."], ["💬", "Friendly support", "Real people ready to help whenever you need us."]],
  steps: [["Tell us what you need", "A quick call or message is all it takes."], ["Get a clear plan", "Transparent pricing with no surprises."], ["Enjoy the results", "We deliver, then make sure you're delighted."]],
  testimonials: [["Professional, friendly and genuinely great value.", "Laura B.", "Customer"], ["They went above and beyond for us.", "Kevin D.", "Customer"], ["I recommend them to everyone I know.", "Asha V.", "Customer"]],
  faq: [["How do I get started?", "Send us a message using the form below and we'll reply within a day."], ["How much does it cost?", "Pricing depends on your needs — we'll give you a clear quote upfront."], ["Where are you based?", "We're local and serve customers across the region."], ["Do you offer guarantees?", "Yes, we stand behind our work with a satisfaction guarantee."]],
};

const SECTION_TITLES = {
  nav: "Navigation", hero: "Hero", features: "Highlights", about: "About", services: "How it works", menu: "Menu", products: "Featured",
  pricing: "Pricing", testimonials: "Testimonials", gallery: "Gallery", stats: "By the numbers", team: "Team", faq: "FAQ", cta: "Call to action",
  contact: "Contact", footer: "Footer", custom: "Section",
};

const COLOR_WORDS = {
  blue: "#2563eb", navy: "#1e3a8a", green: "#15803d", emerald: "#059669", teal: "#0f766e", purple: "#7c3aed", violet: "#7c3aed",
  pink: "#db2777", red: "#dc2626", orange: "#ea580c", yellow: "#ca8a04", gold: "#b7862a", black: "#111111", brown: "#8b5a2b", coral: "#f0604d",
};

const SECTION_KEYWORDS = {
  pricing: ["pricing", "price", "plans", "tiers", "subscription"], testimonials: ["testimonial", "reviews", "review"], gallery: ["gallery", "photos", "portfolio", "work"],
  team: ["team", "staff", "coaches", "speakers", "instructors"], faq: ["faq", "questions"], contact: ["contact", "form", "booking", "reservation", "reservations", "book"],
  menu: ["menu"], stats: ["stats", "numbers", "statistics"], about: ["about", "story", "history"], products: ["products", "listings", "catalog", "catalogue"],
  features: ["features", "benefits"], cta: ["newsletter", "signup", "sign-up", "subscribe"],
};

// -------------------------------------------------------------- understanding

export function analyzePrompt(prompt) {
  const p = ` ${prompt.toLowerCase()} `;
  let best = { id: "generic", score: 0 };
  for (const [id, prof] of Object.entries(PROFILES)) {
    const score = prof.kw.reduce((s, k) => s + (new RegExp(`[^a-z]${k.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}s?[^a-z]`).test(p) ? (k.includes(" ") ? 3 : 2) : 0), 0);
    if (score > best.score) best = { id, score };
  }
  const prof = best.id === "generic" ? GENERIC : PROFILES[best.id];
  const seed = hash(prompt);

  let name = null;
  const quoted = prompt.match(/["“']([^"”']{2,40})["”']/);
  const called = prompt.match(/\b(?:called|named|name is|brand(?:ed)? as)\s+([A-Z0-9][\w'&.-]*(?:\s+(?:&|and|of|the|[A-Z0-9][\w'&.-]*)){0,4})/);
  if (called) name = called[1].replace(/\s+(and|of|the)$/i, "").trim();
  else if (quoted) name = quoted[1].trim();
  else {
    const caps = prompt.match(/\bfor\s+(?:my\s+|our\s+)?([A-Z][\w'&-]+(?:\s+[A-Z][\w'&-]+){0,3})/);
    if (caps) name = caps[1];
  }
  if (!name) name = pick(prof.names, seed);

  const cityM = prompt.match(/\b(?:in|based in|located in|from)\s+([A-Z][a-zA-Z]+(?:[\s-][A-Z][a-zA-Z]+)?)/);
  const city = cityM ? cityM[1] : "";

  // Requested sections from the prompt
  const wanted = [];
  const hasWord = (k) => new RegExp(`[^a-z]${k.replace(/[-]/g, "\\-")}[^a-z]`).test(p);
  for (const [type, kws] of Object.entries(SECTION_KEYWORDS)) if (kws.some(hasWord)) wanted.push(type);

  let colors = [];
  for (const [w, hex] of Object.entries(COLOR_WORDS)) if (new RegExp(`\\b${w}\\b`).test(p)) colors.push(hex);
  const dark = /\b(dark|night|black background|moody)\b/.test(p);
  const light = /\b(light|bright|minimal|airy|white)\b/.test(p);
  const roleM = prompt.match(/\b(photographer|designer|illustrator|developer|artist|architect|writer|musician|copywriter|videographer)\b/i);

  // The user's own description of the business, e.g. "cosy Italian trattoria".
  let descriptor = "";
  const rx = (k) => k.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const kwHit = prof.kw.find((k) => new RegExp(`\\b${rx(k)}`, "i").test(prompt));
  if (kwHit) {
    const m = prompt.match(new RegExp(`\\b(?:a|an|the|my|our)\\s+((?:[A-Za-z'-]+\\s+){0,3}?${rx(kwHit)}[a-z]*)`, "i"));
    if (m && !/\b(called|named|website|site|page|landing)\b/i.test(m[1])) descriptor = m[1].trim();
  }
  return { type: best.id === "generic" ? "business" : best.id, profile: prof, seed, name, city, wanted, colors, dark, light, descriptor, role: roleM ? roleM[1].toLowerCase() : "designer" };
}

function fill(str, a) {
  return String(str || "")
    .replace(/\{name\}/g, a.name)
    .replace(/\{city\}/g, a.city ? ` in ${a.city}` : "")
    .replace(/\{noun\}/g, a.profile.noun)
    .replace(/\{role\}/g, a.role);
}

// ------------------------------------------------------------------- agents

export function demoPlan(prompt) {
  const a = analyzePrompt(prompt);
  const types = [...a.profile.sections];
  for (const w of a.wanted) {
    if (types.includes(w)) continue;
    if (w === "products" && types.includes("menu")) continue;
    if (w === "menu" && types.includes("products")) continue;
    const before = types.indexOf(w === "cta" ? "footer" : types.includes("contact") ? "contact" : "footer");
    types.splice(before, 0, w);
  }
  const purposes = {
    nav: "Let visitors jump to any section and reach the main call to action.",
    hero: "Instantly communicate who this is for and the single most important action.",
    features: "Show the key reasons to choose this over alternatives.",
    about: "Build trust with the story and values behind the brand.",
    services: "Explain what is offered and how it works, step by step.",
    menu: "Present offerings with descriptions and prices.",
    products: "Showcase featured items with key details.",
    pricing: "Make plans and prices easy to compare.",
    testimonials: "Provide social proof from real customers.",
    gallery: "Show the work, space or product visually.",
    stats: "Back up claims with credible numbers.",
    team: "Put faces to the name.",
    faq: "Answer objections before they become blockers.",
    cta: "Give one last, strong nudge to act.",
    contact: "Make it effortless to get in touch or book.",
    footer: "Wrap up with links, contact details and legal info.",
  };
  const sections = types.map((t) => ({
    id: t,
    type: t,
    title: t === "contact" && a.profile.contactTitle ? a.profile.contactTitle : t === "products" && a.type === "realestate" ? "Featured listings" : SECTION_TITLES[t] || cap(t),
    purpose: purposes[t] || "",
  }));
  const tagline = fill(pick(a.profile.hero, a.seed), a);
  return {
    thoughts: `This reads as a ${a.type} website${a.city ? ` based in ${a.city}` : ""}. I'll call it "${a.name}" and structure the page as a visitor journey: hook → proof → offer → action. ` +
      (a.wanted.length ? `The request explicitly mentions ${a.wanted.join(", ")}, so those are included. ` : "") +
      `${sections.length} sections in total.`,
    siteName: a.name,
    tagline,
    siteType: a.type,
    audience: a.type === "saas" ? "Teams and professionals evaluating tools" : a.type === "portfolio" ? "Prospective clients and collaborators" : "Local customers and first-time visitors",
    goals: ["Communicate the offer within 5 seconds", `Drive visitors to "${a.profile.cta}"`, "Build trust with social proof"],
    tone: a.type === "fitness" ? "Energetic and motivating" : a.type === "saas" ? "Confident, clear and friendly" : a.type === "portfolio" ? "Personal and considered" : "Warm and welcoming",
    sections,
  };
}

const LAYOUTS = {
  nav: ["sticky-bar"], hero: ["split-art-right", "centered-gradient"], features: ["3-col-cards"], about: ["split-art-left"], services: ["numbered-steps"],
  menu: ["two-col-list"], products: ["card-grid"], pricing: ["3-tier-highlight-middle"], testimonials: ["quote-cards"], gallery: ["mosaic-grid"],
  stats: ["band-on-primary"], team: ["avatar-cards"], faq: ["accordion"], cta: ["gradient-banner"], contact: ["split-info-form"], footer: ["columns"], custom: ["centered"],
};

export function demoArchitect(site) {
  const layouts = {};
  site.plan.sections.forEach((s, i) => {
    const opts = LAYOUTS[s.type] || LAYOUTS.custom;
    layouts[s.id] = {
      layout: opts[(hash(site.prompt) + i) % opts.length],
      components: [],
      notes: s.type === "hero" ? "Headline, supporting line, two CTAs, visual on the side." : "",
    };
  });
  const nav = site.plan.sections
    .filter((s) => !["nav", "hero", "footer", "cta"].includes(s.type))
    .slice(0, 5)
    .map((s) => ({ label: s.title.length > 18 ? cap(s.type) : s.title, href: `#${s.id}` }));
  return {
    thoughts: `Alternating rhythm: full-width hero, then card grids broken up by split layouts and a colour band so the scroll never feels monotonous. Nav gets ${nav.length} links plus the primary CTA.`,
    nav,
    layouts,
  };
}

export function demoDesigner(site) {
  const a = analyzePrompt(site.prompt);
  let pal = { ...pick(a.profile.palettes, a.seed) };
  if (a.colors.length) {
    pal.primary = a.colors[0];
    if (a.colors[1]) pal.accent = a.colors[1];
  }
  if (a.dark && contrast(pal.bg, "#000000") > 8) {
    pal = { ...pal, bg: "#0f1115", surface: "#1a1d24", text: "#f3f4f6", muted: "#a8afbd", secondary: "#05060a" };
  } else if (a.light && contrast(pal.bg, "#ffffff") > 2) {
    pal = { ...pal, bg: "#ffffff", surface: "#f5f5f7", text: "#141414", muted: "#585b63" };
  }
  const serif = /\b(elegant|luxury|luxurious|classic|editorial|refined)\b/i.test(site.prompt);
  const playful = /\b(playful|fun|kids|colorful|colourful|bold)\b/i.test(site.prompt);
  const fonts = serif ? ["Playfair Display", "Inter"] : playful ? ["Fredoka", "Nunito"] : a.profile.fonts;
  const tokens = normalizeTokens({
    ...pal,
    headingFont: fonts[0],
    bodyFont: fonts[1],
    radius: playful ? "22px" : serif ? "6px" : "14px",
    shadow: "0 12px 32px rgba(15, 23, 42, 0.09)",
    style: `${serif ? "Elegant" : playful ? "Playful" : "Modern"} ${a.type} aesthetic with ${fonts[0]} headings`,
  });
  return {
    thoughts: `A ${tokens.style.toLowerCase()}. Primary ${tokens.primary} anchors calls to action; text/background contrast is ${contrast(tokens.text, tokens.bg).toFixed(1)}:1 and button text is ${contrast(tokens.onPrimary, tokens.primary).toFixed(1)}:1, both above WCAG AA.`,
    tokens,
  };
}

export function demoCopy(site) {
  const a = analyzePrompt(site.prompt);
  const P = a.profile;
  const G = GENERIC;
  const name = site.plan.siteName || a.name;
  const ax = { ...a, name };
  const copy = {};
  const first = site.plan.sections.find((s) => s.type === "contact") || site.plan.sections.find((s) => s.type === "pricing");
  const ctaHref = first ? `#${first.id}` : "#";
  const items = (arr) => (arr || []).map((x) => (Array.isArray(x) ? x : [x]));
  for (const s of site.plan.sections) {
    const c = { eyebrow: "", heading: s.title, subheading: "", body: "", items: [] };
    switch (s.type) {
      case "nav":
        c.heading = name;
        c.cta = { label: P.cta, href: ctaHref };
        break;
      case "hero":
        c.eyebrow = a.descriptor ? `${cap(a.descriptor)}${a.city ? ` · ${a.city}` : ""}` : a.city ? `${cap(P.noun)} · ${a.city}` : `Welcome to ${name}`;
        c.heading = site.plan.tagline || fill(pick(P.hero, a.seed), ax);
        c.subheading = fill(P.sub, ax);
        c.cta = { label: P.cta, href: ctaHref };
        c.secondaryCta = { label: "Learn more", href: `#${site.plan.sections[2]?.id || "about"}` };
        break;
      case "features":
        c.eyebrow = "Why choose us";
        c.heading = `Why people love ${name}`;
        c.items = items(P.features || G.features).map(([icon, title, text]) => ({ icon, title, text }));
        break;
      case "about":
        c.eyebrow = "Our story";
        c.heading = a.type === "portfolio" ? `Hi, I'm ${name}` : `More than just a ${P.noun}`;
        c.body = fill(
          a.type === "portfolio"
            ? "For over a decade I've partnered with founders, editors and agencies to create work that is clear, warm and quietly bold. Every project starts with listening."
            : `${name} is ${a.descriptor ? `a ${a.descriptor}` : `an independent ${P.noun}`}{city} that started with a simple idea: do one thing exceptionally well, and treat everyone who walks through the door like family. Years later, that's still how we work.`,
          ax,
        );
        c.items = ["Independent & locally owned", "Obsessive attention to detail", "Loved by hundreds of customers"].map((t) => ({ title: t }));
        c.cta = { label: "Get in touch", href: ctaHref };
        break;
      case "services":
        c.eyebrow = P.steps ? "How it works" : "What we do";
        c.heading = P.steps ? "Getting started is easy" : "Services";
        c.items = P.steps ? items(P.steps).map(([title, text]) => ({ title, text })) : items(P.features || G.features).map(([icon, title, text]) => ({ icon, title, text }));
        break;
      case "menu":
      case "products":
        c.eyebrow = a.type === "restaurant" ? "From the kitchen" : a.type === "realestate" ? "On the market" : "Bestsellers";
        c.heading = a.type === "restaurant" ? "Our menu" : s.title;
        c.items = items(P.menu || PROFILES.shop.menu).map(([title, text, meta]) => ({ title, text, meta }));
        c.cta = { label: a.type === "restaurant" ? "Book a table" : "View all", href: ctaHref };
        break;
      case "pricing":
        c.eyebrow = "Pricing";
        c.heading = "Simple, transparent pricing";
        c.subheading = "No hidden fees. Change or cancel anytime.";
        c.items = items(P.pricing || PROFILES.saas.pricing).map(([title, meta, text, feats]) => ({ title, meta, text, features: feats }));
        c.cta = { label: "Choose plan", href: ctaHref };
        break;
      case "testimonials":
        c.eyebrow = "Kind words";
        c.heading = "What people are saying";
        c.items = items(P.testimonials || G.testimonials).map(([text, title, meta]) => ({ text: fill(text, ax), title, meta }));
        break;
      case "gallery":
        c.eyebrow = a.type === "portfolio" || a.type === "agency" ? "Selected work" : "Take a look";
        c.heading = a.type === "portfolio" || a.type === "agency" ? "Recent projects" : "Gallery";
        c.items = (P.gallery || PROFILES.restaurant.gallery).map((g) => ({ icon: [...g][0], title: g.replace(/^\S+\s/, "") }));
        break;
      case "stats":
        c.heading = "By the numbers";
        c.items = items(P.stats || PROFILES.agency.stats).map(([title, text]) => ({ title, text }));
        break;
      case "team":
        c.eyebrow = "The people";
        c.heading = a.type === "event" ? "Featured speakers" : "Meet the team";
        c.items = items(P.team || PROFILES.agency.team).map(([title, text]) => ({ title, text }));
        break;
      case "faq":
        c.eyebrow = "FAQ";
        c.heading = "Questions, answered";
        c.items = items(P.faq || G.faq).map(([title, text]) => ({ title, text }));
        break;
      case "cta":
        c.heading = a.type === "nonprofit" ? "Your support changes lives" : `Ready to get started with ${name}?`;
        c.subheading = a.type === "shop" ? "Join our newsletter for 10% off your first order." : "It only takes a minute — and we'd love to hear from you.";
        c.cta = { label: P.cta, href: ctaHref };
        break;
      case "contact":
        c.eyebrow = "Contact";
        c.heading = s.title;
        c.body = `Drop us a line and we'll get back to you within one business day.`;
        c.items = [
          { icon: "📍", title: a.city ? `12 Market Street, ${a.city}` : "12 Market Street" },
          { icon: "📞", title: "(555) 012-3456" },
          { icon: "✉️", title: `hello@${name.toLowerCase().replace(/[^a-z0-9]+/g, "")}.com` },
        ];
        c.cta = { label: P.contactTitle && /book|reserve/i.test(P.contactTitle) ? "Request booking" : "Send message" };
        break;
      case "footer":
        c.heading = name;
        c.body = site.plan.tagline || "";
        break;
      default:
        c.body = s.purpose;
    }
    copy[s.id] = c;
  }
  return {
    thoughts: `Tone: ${site.plan.tone || "friendly"}. Headlines lead with the benefit, CTAs use concrete verbs ("${P.cta}"), and proof (testimonials, numbers) sits right before the asks.`,
    copy,
  };
}

// ---------------------------------------------------------------- developer

function navLinks(site) {
  return site.nav?.length ? site.nav : site.plan.sections.filter((s) => !["nav", "hero", "footer"].includes(s.type)).slice(0, 5).map((s) => ({ label: s.title, href: `#${s.id}` }));
}

const art = (emoji, label) => `<div class="art" role="img" aria-label="${esc(label)}"><span aria-hidden="true">${emoji}</span></div>`;

export function demoSection(section, site) {
  const c = site.copy[section.id] || { heading: section.title, items: [] };
  const id = section.id;
  const items = c.items || [];
  const layout = site.layouts?.[id]?.layout || "";
  const a = analyzePrompt(site.prompt);
  const emoji = a.profile.emoji;
  const cta = c.cta ? `<a class="btn btn-primary" href="${esc(c.cta.href || "#")}">${esc(c.cta.label)}</a>` : "";
  const cta2 = c.secondaryCta ? `<a class="btn btn-outline" href="${esc(c.secondaryCta.href)}">${esc(c.secondaryCta.label)}</a>` : "";
  const head = (center = true) =>
    `<div class="head${center ? " center" : ""} reveal">${c.eyebrow ? `<span class="eyebrow">${esc(c.eyebrow)}</span>` : ""}<h2>${esc(c.heading)}</h2>${c.subheading ? `<p class="lead">${esc(c.subheading)}</p>` : ""}</div>`;
  const headCss = `#${id} .head{max-width:680px;margin-bottom:2.5rem}#${id} .head.center{margin-inline:auto;text-align:center}#${id} .lead{color:var(--color-muted);font-size:1.15rem}`;
  let html = "";
  let css = "";

  switch (section.type) {
    case "nav": {
      const links = navLinks(site);
      html = `<header id="${id}" class="site-nav">
  <div class="container bar">
    <a class="brand" href="#">${a.profile.emoji.length <= 2 ? `<span class="logo" aria-hidden="true">${emoji}</span>` : ""}${esc(site.plan.siteName)}</a>
    <button class="nav-toggle" data-nav-toggle aria-expanded="false" aria-label="Open menu"><span></span><span></span><span></span></button>
    <nav data-nav-menu aria-label="Main">
      <ul>${links.map((l) => `<li><a href="${esc(l.href)}">${esc(l.label)}</a></li>`).join("")}</ul>
      ${cta.replace("btn btn-primary", "btn btn-primary btn-sm")}
    </nav>
  </div>
</header>`;
      css = `#${id}{position:sticky;top:0;z-index:50;background:color-mix(in srgb,var(--color-bg) 88%,transparent);backdrop-filter:blur(12px);border-bottom:1px solid color-mix(in srgb,var(--color-text) 8%,transparent)}
#${id} .bar{display:flex;align-items:center;justify-content:space-between;gap:1rem;min-height:72px}
#${id} .brand{display:flex;align-items:center;gap:.55rem;font-family:var(--font-heading);font-weight:800;font-size:1.3rem;color:var(--color-text);text-decoration:none}
#${id} .logo{display:grid;place-items:center;width:36px;height:36px;border-radius:10px;background:var(--color-primary);color:var(--color-on-primary);font-size:1.05rem}
#${id} nav{display:flex;align-items:center;gap:2rem}
#${id} ul{display:flex;gap:1.6rem;list-style:none;margin:0;padding:0}
#${id} ul a{color:var(--color-text);text-decoration:none;font-weight:500;opacity:.85}
#${id} ul a:hover{color:var(--color-primary-text);opacity:1}
#${id} .btn-sm{padding:.6rem 1.15rem;font-size:.92rem}
#${id} .nav-toggle{display:none;background:none;border:0;padding:.5rem;cursor:pointer;flex-direction:column;gap:5px}
#${id} .nav-toggle span{display:block;width:24px;height:2px;background:var(--color-text);border-radius:2px}
@media (max-width:820px){
#${id} .nav-toggle{display:flex}
#${id} nav{display:none;position:absolute;left:0;right:0;top:72px;flex-direction:column;align-items:stretch;padding:1rem 1.25rem 1.5rem;background:var(--color-bg);box-shadow:var(--shadow)}
#${id} nav.is-open{display:flex}
#${id} ul{flex-direction:column;gap:.25rem}
#${id} ul a{display:block;padding:.7rem 0}
}`;
      break;
    }
    case "hero": {
      const centered = layout.includes("center");
      html = `<section id="${id}" class="hero${centered ? " centered" : ""}">
  <div class="container inner">
    <div class="copy reveal">
      ${c.eyebrow ? `<span class="eyebrow">${esc(c.eyebrow)}</span>` : ""}
      <h1>${esc(c.heading)}</h1>
      <p class="lead">${esc(c.subheading)}</p>
      <div class="actions">${cta}${cta2}</div>
    </div>
    ${centered ? "" : `<div class="visual reveal">${art(emoji, `${site.plan.siteName} illustration`)}<div class="badge b1">⭐ 4.9 rating</div><div class="badge b2">✓ Loved locally</div></div>`}
  </div>
</section>`;
      css = `#${id}{position:relative;overflow:hidden;padding-block:clamp(4rem,10vw,7.5rem);background:radial-gradient(1200px 500px at 85% -10%,color-mix(in srgb,var(--color-primary) 18%,transparent),transparent),radial-gradient(800px 400px at -10% 110%,color-mix(in srgb,var(--color-accent) 18%,transparent),transparent)}
#${id} .inner{display:grid;grid-template-columns:1.1fr .9fr;gap:clamp(2rem,5vw,4rem);align-items:center}
#${id}.centered .inner{grid-template-columns:1fr;text-align:center;max-width:860px}
#${id} .lead{font-size:clamp(1.05rem,1.6vw,1.25rem);color:var(--color-muted);max-width:560px}
#${id}.centered .lead{margin-inline:auto}
#${id} .actions{display:flex;flex-wrap:wrap;gap:.8rem;margin-top:1.8rem}
#${id}.centered .actions{justify-content:center}
#${id} .visual{position:relative}
#${id} .art{aspect-ratio:4/4.4;border-radius:calc(var(--radius) * 2);display:grid;place-items:center;font-size:clamp(5rem,12vw,9rem);background:linear-gradient(140deg,var(--color-primary),color-mix(in srgb,var(--color-primary) 40%,var(--color-accent)));box-shadow:var(--shadow)}
#${id} .badge{position:absolute;background:var(--color-bg);color:var(--color-text);padding:.65rem 1rem;border-radius:999px;font-weight:600;font-size:.9rem;box-shadow:var(--shadow)}
#${id} .b1{top:10%;left:-6%}#${id} .b2{bottom:12%;right:-4%}
@media (max-width:860px){#${id} .inner{grid-template-columns:1fr}#${id} .badge{display:none}}`;
      break;
    }
    case "features":
    case "services": {
      const steps = !items[0]?.icon;
      html = `<section id="${id}" class="section-pad">
  <div class="container">
    ${head()}
    <div class="grid-auto">
      ${items
        .map(
          (it, i) => `<article class="card item reveal">
        <div class="icon" aria-hidden="true">${steps ? String(i + 1).padStart(2, "0") : esc(it.icon)}</div>
        <h3>${esc(it.title)}</h3>
        <p>${esc(it.text)}</p>
      </article>`,
        )
        .join("\n      ")}
    </div>
  </div>
</section>`;
      css = `${headCss}
#${id}${section.type === "services" ? "{background:var(--color-surface)}" : "{}"}
#${id} .item{background:${section.type === "services" ? "var(--color-bg)" : "var(--color-surface)"};transition:transform .25s ease,box-shadow .25s ease}
#${id} .item:hover{transform:translateY(-4px)}
#${id} .icon{display:grid;place-items:center;width:52px;height:52px;border-radius:14px;margin-bottom:1.1rem;font-size:1.5rem;font-weight:800;font-family:var(--font-heading);background:color-mix(in srgb,var(--color-primary) 14%,transparent);color:var(--color-primary-text)}
#${id} p{color:var(--color-muted);margin:0}`;
      break;
    }
    case "about": {
      html = `<section id="${id}" class="section-pad">
  <div class="container split">
    ${art(a.type === "portfolio" ? "🧑‍🎨" : emoji, `About ${site.plan.siteName}`)}
    <div class="text reveal">
      ${c.eyebrow ? `<span class="eyebrow">${esc(c.eyebrow)}</span>` : ""}
      <h2>${esc(c.heading)}</h2>
      <p>${esc(c.body)}</p>
      <ul class="checks">${items.map((it) => `<li>${esc(it.title)}</li>`).join("")}</ul>
      ${cta}
    </div>
  </div>
</section>`;
      css = `#${id} .split{display:grid;grid-template-columns:.9fr 1.1fr;gap:clamp(2rem,5vw,4.5rem);align-items:center}
#${id} .art{aspect-ratio:1;border-radius:calc(var(--radius) * 2);display:grid;place-items:center;font-size:clamp(4rem,10vw,7rem);background:linear-gradient(160deg,color-mix(in srgb,var(--color-accent) 70%,var(--color-bg)),color-mix(in srgb,var(--color-primary) 60%,var(--color-bg)))}
#${id} p{color:var(--color-muted);font-size:1.1rem}
#${id} .checks{list-style:none;padding:0;margin:1.5rem 0 2rem;display:grid;gap:.7rem}
#${id} .checks li{display:flex;gap:.7rem;align-items:center;font-weight:600}
#${id} .checks li::before{content:"✓";display:grid;place-items:center;width:26px;height:26px;border-radius:50%;flex:none;background:var(--color-primary);color:var(--color-on-primary);font-size:.85rem}
@media (max-width:820px){#${id} .split{grid-template-columns:1fr}}`;
      break;
    }
    case "menu":
    case "products": {
      const asCards = section.type === "products";
      html = `<section id="${id}" class="section-pad">
  <div class="container">
    ${head()}
    <div class="${asCards ? "grid-auto" : "list"}">
      ${items
        .map((it, i) =>
          asCards
            ? `<article class="card product reveal"><div class="thumb" aria-hidden="true">${pick(["🏷️", "✨", "🎁", "🌿", "🏠", "💎"], i)}</div><div class="row"><h3>${esc(it.title)}</h3><span class="price">${esc(it.meta)}</span></div><p>${esc(it.text)}</p></article>`
            : `<div class="dish reveal"><div><h3>${esc(it.title)}</h3><p>${esc(it.text)}</p></div><span class="dots" aria-hidden="true"></span><span class="price">${esc(it.meta)}</span></div>`,
        )
        .join("\n      ")}
    </div>
    ${cta ? `<div class="more">${cta}</div>` : ""}
  </div>
</section>`;
      css = `${headCss}
#${id}{background:var(--color-surface)}
#${id} .list{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr));gap:1.6rem 3.5rem}
#${id} .dish{display:flex;align-items:baseline;gap:.8rem}
#${id} .dish h3{margin:0 0 .2rem;font-size:1.15rem}
#${id} .dish p{margin:0;color:var(--color-muted);font-size:.95rem}
#${id} .dots{flex:1;border-bottom:2px dotted color-mix(in srgb,var(--color-text) 25%,transparent);transform:translateY(-6px);min-width:20px}
#${id} .price{font-family:var(--font-heading);font-weight:700;color:var(--color-primary-text);white-space:nowrap}
#${id} .product{background:var(--color-bg);padding:1rem}
#${id} .thumb{aspect-ratio:4/3;border-radius:calc(var(--radius) - 4px);display:grid;place-items:center;font-size:3rem;margin-bottom:1rem;background:linear-gradient(135deg,color-mix(in srgb,var(--color-primary) 22%,var(--color-bg)),color-mix(in srgb,var(--color-accent) 30%,var(--color-bg)))}
#${id} .row{display:flex;justify-content:space-between;gap:1rem;align-items:baseline}
#${id} .row h3{margin:0;font-size:1.1rem}
#${id} .product p{color:var(--color-muted);margin:.4rem 0 0;font-size:.95rem}
#${id} .more{text-align:center;margin-top:2.5rem}`;
      break;
    }
    case "pricing": {
      html = `<section id="${id}" class="section-pad">
  <div class="container">
    ${head()}
    <div class="plans">
      ${items
        .map(
          (it, i) => `<article class="plan card reveal${i === 1 ? " featured" : ""}">
        ${i === 1 ? `<span class="tag">Most popular</span>` : ""}
        <h3>${esc(it.title)}</h3>
        <p class="price"><strong>${esc(it.meta)}</strong></p>
        <p class="desc">${esc(it.text)}</p>
        <ul>${(it.features || []).map((f) => `<li>${esc(f)}</li>`).join("")}</ul>
        <a class="btn ${i === 1 ? "btn-primary" : "btn-outline"}" href="${esc(c.cta?.href || "#")}">${esc(c.cta?.label || "Choose")}</a>
      </article>`,
        )
        .join("\n      ")}
    </div>
  </div>
</section>`;
      css = `${headCss}
#${id} .plans{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr));gap:1.5rem;align-items:stretch}
#${id} .plan{position:relative;display:flex;flex-direction:column;padding:2rem}
#${id} .featured{background:var(--color-secondary);color:#fff;transform:scale(1.03)}
#${id} .featured .desc,#${id} .featured li{color:rgba(255,255,255,.82)}
#${id} .featured .btn-primary{box-shadow:none}
#${id} .tag{position:absolute;top:-12px;left:2rem;background:var(--color-accent);color:#111;font-size:.75rem;font-weight:800;padding:.3rem .75rem;border-radius:999px;text-transform:uppercase;letter-spacing:.06em}
#${id} .price strong{font-family:var(--font-heading);font-size:2.6rem}
#${id} .desc{color:var(--color-muted)}
#${id} ul{list-style:none;padding:0;margin:0 0 1.8rem;display:grid;gap:.55rem;flex:1}
#${id} li::before{content:"✓  ";color:var(--color-accent);font-weight:800}
#${id} .plan .btn{width:100%}
@media (max-width:700px){#${id} .featured{transform:none}}`;
      break;
    }
    case "testimonials": {
      html = `<section id="${id}" class="section-pad">
  <div class="container">
    ${head()}
    <div class="grid-auto">
      ${items
        .map(
          (it) => `<figure class="card quote reveal">
        <div class="stars" aria-label="5 out of 5 stars">★★★★★</div>
        <blockquote>“${esc(it.text)}”</blockquote>
        <figcaption><span class="avatar" aria-hidden="true">${esc((it.title || "?")[0])}</span><span><strong>${esc(it.title)}</strong><small>${esc(it.meta || "")}</small></span></figcaption>
      </figure>`,
        )
        .join("\n      ")}
    </div>
  </div>
</section>`;
      css = `${headCss}
#${id} .quote{margin:0;display:flex;flex-direction:column;gap:1rem}
#${id} .stars{color:var(--color-accent);letter-spacing:.15em}
#${id} blockquote{margin:0;font-size:1.08rem;flex:1}
#${id} figcaption{display:flex;align-items:center;gap:.8rem}
#${id} figcaption small{display:block;color:var(--color-muted)}
#${id} .avatar{display:grid;place-items:center;width:44px;height:44px;border-radius:50%;background:var(--color-primary);color:var(--color-on-primary);font-weight:800}`;
      break;
    }
    case "gallery": {
      html = `<section id="${id}" class="section-pad">
  <div class="container">
    ${head()}
    <div class="mosaic">
      ${items.map((it, i) => `<figure class="tile t${i % 6} reveal" role="img" aria-label="${esc(it.title)}"><span aria-hidden="true">${esc(it.icon)}</span><figcaption>${esc(it.title)}</figcaption></figure>`).join("\n      ")}
    </div>
  </div>
</section>`;
      css = `${headCss}
#${id} .mosaic{display:grid;grid-template-columns:repeat(4,1fr);grid-auto-rows:190px;gap:1rem}
#${id} .tile{position:relative;margin:0;border-radius:var(--radius);overflow:hidden;display:grid;place-items:center;font-size:3.4rem;transition:transform .3s ease}
#${id} .tile:hover{transform:scale(1.02)}
#${id} .t0{grid-column:span 2;grid-row:span 2;font-size:5rem;background:linear-gradient(135deg,var(--color-primary),var(--color-accent))}
#${id} .t1{background:linear-gradient(135deg,color-mix(in srgb,var(--color-accent) 75%,#fff),var(--color-accent))}
#${id} .t2{background:linear-gradient(135deg,var(--color-secondary),var(--color-primary))}
#${id} .t3{grid-column:span 2;background:linear-gradient(135deg,color-mix(in srgb,var(--color-primary) 55%,#fff),var(--color-primary))}
#${id} .t4{background:linear-gradient(135deg,var(--color-accent),var(--color-primary))}
#${id} .t5{background:linear-gradient(135deg,var(--color-primary),var(--color-secondary))}
#${id} figcaption{position:absolute;left:.75rem;bottom:.75rem;background:rgba(0,0,0,.6);color:#fff;font-size:.85rem;font-weight:600;padding:.35rem .7rem;border-radius:999px}
@media (max-width:760px){#${id} .mosaic{grid-template-columns:repeat(2,1fr);grid-auto-rows:150px}#${id} .t0{grid-column:span 2}#${id} .t3{grid-column:span 2}}`;
      break;
    }
    case "stats": {
      html = `<section id="${id}" class="band">
  <div class="container">
    <h2 class="sr-only">${esc(c.heading)}</h2>
    <dl class="stats">
      ${items.map((it) => `<div class="stat reveal"><dt>${esc(it.text)}</dt><dd>${esc(it.title)}</dd></div>`).join("\n      ")}
    </dl>
  </div>
</section>`;
      css = `#${id}{background:var(--color-primary);color:var(--color-on-primary);padding-block:clamp(2.5rem,6vw,4rem)}
#${id} .sr-only{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
#${id} .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,180px),1fr));gap:2rem;margin:0;text-align:center}
#${id} .stat{display:flex;flex-direction:column-reverse}
#${id} dd{margin:0;font-family:var(--font-heading);font-size:clamp(2rem,4.5vw,3rem);font-weight:800;line-height:1.1}
#${id} dt{opacity:.9;font-weight:500}`;
      break;
    }
    case "team": {
      html = `<section id="${id}" class="section-pad">
  <div class="container">
    ${head()}
    <div class="grid-auto">
      ${items
        .map(
          (it, i) => `<article class="member reveal">
        <div class="photo p${i % 4}" role="img" aria-label="Portrait of ${esc(it.title)}"><span aria-hidden="true">${esc(it.title.split(" ").filter((w) => /^[A-Z]/.test(w)).map((w) => w[0]).slice(-2).join(""))}</span></div>
        <h3>${esc(it.title)}</h3><p>${esc(it.text)}</p>
      </article>`,
        )
        .join("\n      ")}
    </div>
  </div>
</section>`;
      css = `${headCss}
#${id}{background:var(--color-surface)}
#${id} .member{text-align:center}
#${id} .photo{aspect-ratio:1;border-radius:var(--radius);display:grid;place-items:center;font-family:var(--font-heading);font-size:2.6rem;font-weight:800;color:#fff;margin-bottom:1rem}
#${id} .p0{background:linear-gradient(135deg,var(--color-primary),var(--color-secondary))}
#${id} .p1{background:linear-gradient(135deg,var(--color-accent),var(--color-primary))}
#${id} .p2{background:linear-gradient(135deg,var(--color-secondary),var(--color-accent))}
#${id} .p3{background:linear-gradient(135deg,var(--color-primary),var(--color-accent))}
#${id} h3{margin:0}#${id} p{color:var(--color-muted);margin:.2rem 0 0}`;
      break;
    }
    case "faq": {
      html = `<section id="${id}" class="section-pad">
  <div class="container narrow">
    ${head()}
    <div class="faqs">
      ${items.map((it, i) => `<details class="reveal"${i === 0 ? " open" : ""}><summary>${esc(it.title)}</summary><p>${esc(it.text)}</p></details>`).join("\n      ")}
    </div>
  </div>
</section>`;
      css = `${headCss}
#${id} .narrow{max-width:800px}
#${id} .faqs{display:grid;gap:.8rem}
#${id} details{background:var(--color-surface);border-radius:var(--radius);padding:1.1rem 1.4rem}
#${id} summary{cursor:pointer;font-weight:700;font-size:1.08rem;list-style:none;display:flex;justify-content:space-between;gap:1rem}
#${id} summary::-webkit-details-marker{display:none}
#${id} summary::after{content:"+";color:var(--color-primary-text);font-size:1.4rem;line-height:1}
#${id} details[open] summary::after{content:"–"}
#${id} details p{margin:.8rem 0 0;color:var(--color-muted)}`;
      break;
    }
    case "cta": {
      html = `<section id="${id}" class="section-pad">
  <div class="container">
    <div class="banner reveal">
      <h2>${esc(c.heading)}</h2>
      ${c.subheading ? `<p>${esc(c.subheading)}</p>` : ""}
      ${c.cta ? `<a class="btn btn-light" href="${esc(c.cta.href || "#")}">${esc(c.cta.label)}</a>` : ""}
    </div>
  </div>
</section>`;
      css = `#${id} .banner{text-align:center;padding:clamp(2.5rem,6vw,4.5rem) clamp(1.5rem,5vw,4rem);border-radius:calc(var(--radius) * 2);color:#fff;background:linear-gradient(120deg,var(--color-secondary),color-mix(in srgb,var(--color-primary) 70%,var(--color-secondary)))}
#${id} p{opacity:.9;font-size:1.15rem;max-width:560px;margin:0 auto 1.8rem}
#${id} .btn-light{background:#fff;color:#111}`;
      break;
    }
    case "contact": {
      html = `<section id="${id}" class="section-pad">
  <div class="container split">
    <div class="info reveal">
      ${c.eyebrow ? `<span class="eyebrow">${esc(c.eyebrow)}</span>` : ""}
      <h2>${esc(c.heading)}</h2>
      <p>${esc(c.body)}</p>
      <ul>${items.map((it) => `<li><span aria-hidden="true">${esc(it.icon)}</span>${esc(it.title)}</li>`).join("")}</ul>
    </div>
    <form class="card form reveal" data-demo-form>
      <div class="row2">
        <label>Name<input name="name" type="text" autocomplete="name" required></label>
        <label>Email<input name="email" type="email" autocomplete="email" required></label>
      </div>
      ${/book|reserv/i.test(c.cta?.label || "") ? `<div class="row2"><label>Date<input name="date" type="date" required></label><label>Guests<input name="guests" type="number" min="1" max="20" value="2"></label></div>` : ""}
      <label>Message<textarea name="message" rows="4"></textarea></label>
      <button class="btn btn-primary" type="submit">${esc(c.cta?.label || "Send message")}</button>
    </form>
  </div>
</section>`;
      css = `#${id}{background:var(--color-surface)}
#${id} .split{display:grid;grid-template-columns:.9fr 1.1fr;gap:clamp(2rem,5vw,4rem);align-items:start}
#${id} .info p{color:var(--color-muted);font-size:1.1rem}
#${id} ul{list-style:none;padding:0;margin:1.5rem 0 0;display:grid;gap:.9rem}
#${id} li{display:flex;gap:.75rem;align-items:center;font-weight:600}
#${id} .form{background:var(--color-bg);display:grid;gap:1rem;padding:clamp(1.4rem,3vw,2.2rem)}
#${id} .row2{display:grid;grid-template-columns:1fr 1fr;gap:1rem}
#${id} label{display:grid;gap:.35rem;font-weight:600;font-size:.92rem}
#${id} input,#${id} textarea{font:inherit;padding:.8rem 1rem;border-radius:calc(var(--radius) - 4px);border:1.5px solid color-mix(in srgb,var(--color-text) 18%,transparent);background:var(--color-bg);color:var(--color-text)}
#${id} input:focus,#${id} textarea:focus{outline:none;border-color:var(--color-primary);box-shadow:0 0 0 3px color-mix(in srgb,var(--color-primary) 25%,transparent)}
#${id} .form-success{background:color-mix(in srgb,var(--color-primary) 12%,transparent);padding:1rem;border-radius:var(--radius);font-weight:600}
@media (max-width:820px){#${id} .split{grid-template-columns:1fr}#${id} .row2{grid-template-columns:1fr}}`;
      break;
    }
    case "footer": {
      const links = navLinks(site);
      html = `<footer id="${id}">
  <div class="container cols">
    <div><p class="brand">${esc(site.plan.siteName)}</p><p class="muted">${esc(c.body)}</p></div>
    <nav aria-label="Footer"><h3>Explore</h3><ul>${links.map((l) => `<li><a href="${esc(l.href)}">${esc(l.label)}</a></li>`).join("")}</ul></nav>
    <div><h3>Follow</h3><ul><li><a href="#">Instagram</a></li><li><a href="#">LinkedIn</a></li><li><a href="#">Newsletter</a></li></ul></div>
  </div>
  <div class="container legal"><small>© <span data-year>${new Date().getFullYear()}</span> ${esc(site.plan.siteName)}. All rights reserved.</small></div>
</footer>`;
      css = `#${id}{background:var(--color-secondary);color:rgba(255,255,255,.85);padding-top:4rem}
#${id} .cols{display:grid;grid-template-columns:2fr 1fr 1fr;gap:2rem}
#${id} .brand{font-family:var(--font-heading);font-size:1.5rem;font-weight:800;color:#fff;margin:0 0 .5rem}
#${id} .muted{max-width:340px;color:rgba(255,255,255,.75)}
#${id} h3{font-size:.85rem;text-transform:uppercase;letter-spacing:.12em;color:#fff}
#${id} ul{list-style:none;padding:0;margin:0;display:grid;gap:.5rem}
#${id} a{color:rgba(255,255,255,.85);text-decoration:none}
#${id} a:hover{color:#fff;text-decoration:underline}
#${id} .legal{border-top:1px solid rgba(255,255,255,.14);margin-top:3rem;padding-block:1.5rem}
@media (max-width:700px){#${id} .cols{grid-template-columns:1fr}}`;
      break;
    }
    default: {
      html = `<section id="${id}" class="section-pad">
  <div class="container">
    ${head()}
    ${c.body ? `<p class="body reveal">${esc(c.body)}</p>` : ""}
    ${items.length ? `<div class="grid-auto">${items.map((it) => `<article class="card reveal"><h3>${esc(it.title)}</h3><p>${esc(it.text || "")}</p></article>`).join("")}</div>` : ""}
  </div>
</section>`;
      css = `${headCss}#${id} .body{max-width:720px;margin:0 auto 2rem;text-align:center;color:var(--color-muted)}`;
    }
  }
  const thoughts = {
    nav: "Sticky, translucent bar with a collapsible menu under 820px; the CTA stays visible.",
    hero: "Big fluid headline with clamp(), two CTAs, and an illustrated visual card with floating trust badges.",
    footer: "Dark footer with brand, links and legal row — collapses to one column on mobile.",
  }[section.type] || `Built "${section.title}" as ${layout || "a responsive grid"} using the shared tokens; everything scoped to #${id}.`;
  return { thoughts, html, css };
}

export const DEMO_JS = `// Mobile navigation
const toggle = document.querySelector('[data-nav-toggle]');
const menu = document.querySelector('[data-nav-menu]');
if (toggle && menu) {
  toggle.addEventListener('click', () => {
    const open = menu.classList.toggle('is-open');
    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
  });
}

// Smooth in-page scrolling (also closes the mobile menu)
document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener('click', (e) => {
    const id = link.getAttribute('href');
    if (!id || id === '#') return;
    const target = document.querySelector(id);
    if (!target) return;
    e.preventDefault();
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    if (menu && menu.classList.contains('is-open')) {
      menu.classList.remove('is-open');
      toggle && toggle.setAttribute('aria-expanded', 'false');
    }
  });
});

// Reveal on scroll
const revealEls = document.querySelectorAll('.reveal');
if ('IntersectionObserver' in window && revealEls.length) {
  document.documentElement.classList.add('js-reveal');
  const io = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        io.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
  revealEls.forEach((el) => io.observe(el));
}

// Friendly form confirmation
document.querySelectorAll('[data-demo-form]').forEach((form) => {
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const name = (form.querySelector('[name="name"]') || {}).value || 'there';
    const msg = document.createElement('p');
    msg.className = 'form-success';
    msg.setAttribute('role', 'status');
    msg.textContent = 'Thanks, ' + name.split(' ')[0] + '! We\\'ll be in touch shortly.';
    form.replaceChildren(msg);
  });
});

// Keep the footer year current
document.querySelectorAll('[data-year]').forEach((el) => { el.textContent = new Date().getFullYear(); });
`;

export function demoInteraction() {
  return {
    thoughts: "Four small behaviours: accessible mobile menu, smooth anchor scrolling, IntersectionObserver reveals (only enabled once JS runs, so content never hides) and inline form confirmation.",
    js: DEMO_JS,
  };
}

// --------------------------------------------------------- review & evaluation

export function demoQa(site, checks) {
  const issues = [];
  for (const c of checks.items) {
    if (c.pass) continue;
    issues.push({ sectionId: c.sectionId || "global", severity: c.severity || "medium", issue: c.detail || c.label, fix: c.fix || `Fix: ${c.label}` });
  }
  return {
    thoughts: `Ran ${checks.items.length} automated checks across ${site.sections.length} sections, then reviewed structure and copy. ${issues.length ? `${issues.length} issue(s) need attention.` : "Nothing blocking — structure, labels and contrast all look right."}`,
    summary: issues.length ? `${issues.length} issue(s) found.` : "No blocking issues found.",
    issues: issues.slice(0, 8),
  };
}

export function demoEvaluate(site, checks) {
  const s = checks.scores;
  const planned = site.plan.sections.length;
  const built = site.sections.filter((x) => x.html).length;
  const coverage = checks.keywordCoverage ?? 0.8;
  const scores = {
    promptFidelity: Math.round(Math.min(98, 70 + coverage * 22 + (built / planned) * 6)),
    visualDesign: Math.round(Math.min(95, 82 + (contrast(site.tokens.onPrimary, site.tokens.primary) > 4.5 ? 5 : 0) + (site.sections.length >= 7 ? 4 : 0))),
    content: Math.round(Math.min(95, 80 + Math.min(10, site.sections.length) + (coverage > 0.7 ? 3 : 0))),
    accessibility: s.accessibility,
    responsiveness: s.responsiveness,
    codeQuality: s.codeQuality,
  };
  const improvements = checks.items.filter((c) => !c.pass && c.sectionId).slice(0, 4).map((c) => ({ sectionId: c.sectionId, instruction: c.fix || c.label }));
  return {
    thoughts: `Combined ${checks.items.length} automated checks with a read-through of the page. Prompt keyword coverage is ${Math.round(coverage * 100)}%, ${built}/${planned} planned sections shipped.`,
    scores,
    verdict: improvements.length ? "Solid foundation; a few targeted fixes will lift accessibility and polish." : "Cohesive, on-brief and accessible — ready to ship.",
    strengths: ["Consistent design tokens across every section", "Clear primary call to action repeated through the page", "Semantic, responsive markup"],
    improvements,
  };
}

/** Revise a section without an LLM: apply generic automated fixes. */
export function demoRevise(section, instruction, site) {
  let html = section.html;
  let css = section.css;
  const notes = [];
  if (/alt/i.test(instruction)) {
    html = html.replace(/<img(?![^>]*\balt=)([^>]*)>/gi, `<img alt="${esc(section.title)}"$1>`);
    notes.push("added alt text");
  }
  if (/label/i.test(instruction)) {
    html = html.replace(/<(input|textarea|select)(?![^>]*aria-label)([^>]*name="([^"]+)"[^>]*)>/gi, (m, tag, rest, name) => `<${tag} aria-label="${cap(name)}"${rest}>`);
    notes.push("labelled form fields");
  }
  if (/heading/i.test(instruction) && /<h1/i.test(html) && section.type !== "hero") {
    html = html.replace(/<h1/gi, "<h2").replace(/<\/h1>/gi, "</h2>");
    notes.push("fixed heading level");
  }
  if (/overflow|horizontal|responsive|mobile/i.test(instruction)) {
    css += `\n#${section.id}{overflow-x:clip}\n#${section.id} *{min-width:0;overflow-wrap:anywhere}`;
    notes.push("constrained overflow on small screens");
  }
  if (/contrast/i.test(instruction)) {
    css += `\n#${section.id} p,#${section.id} small{color:var(--color-text)}`;
    notes.push("raised text contrast");
  }
  if (!notes.length) {
    // Regenerate from the (possibly updated) copy/tokens.
    const fresh = demoSection(section, site);
    html = fresh.html;
    css = fresh.css;
    notes.push("rebuilt section from the latest copy and tokens");
  }
  return { thoughts: `Applied: ${notes.join(", ")}.`, html, css };
}

/** Interpret a change request on an existing site without an LLM. */
export function demoRefinePlan(site, request) {
  const r = ` ${request.toLowerCase()} `;
  const tokens = {};
  const changes = [];
  const newSections = [];
  const removeSections = [];
  let note = [];
  for (const [w, hex] of Object.entries(COLOR_WORDS)) {
    if (new RegExp(`\\b${w}\\b`).test(r)) {
      tokens.primary = hex;
      note.push(`switch the primary colour to ${w}`);
      break;
    }
  }
  if (/\bdark\b/.test(r)) {
    Object.assign(tokens, { bg: "#0f1115", surface: "#1a1d24", text: "#f3f4f6", muted: "#a8afbd", secondary: "#05060a" });
    note.push("move to a dark theme");
  } else if (/\b(light|white)\b/.test(r)) {
    Object.assign(tokens, { bg: "#ffffff", surface: "#f5f5f7", text: "#141414", muted: "#585b63" });
    note.push("move to a light theme");
  }
  if (/\b(serif|elegant|classic)\b/.test(r)) {
    Object.assign(tokens, { headingFont: "Playfair Display" });
    note.push("use an elegant serif for headings");
  }
  if (/\b(round|rounded|softer)\b/.test(r)) {
    tokens.radius = "24px";
    note.push("round the corners");
  }
  const existing = new Set(site.sections.map((s) => s.type));
  for (const [type, kws] of Object.entries(SECTION_KEYWORDS)) {
    const mentioned = kws.some((k) => r.includes(` ${k}`));
    if (!mentioned) continue;
    if (/\b(remove|delete|drop|without)\b/.test(r) && existing.has(type)) {
      const s = site.sections.find((x) => x.type === type);
      removeSections.push(s.id);
      note.push(`remove the ${s.title} section`);
    } else if (!existing.has(type) && /\b(add|include|with|need|want)\b/.test(r)) {
      const after = site.sections[site.sections.length - 2]?.id;
      newSections.push({ id: type, type, title: SECTION_TITLES[type] || cap(type), purpose: "Requested by the user", after });
      note.push(`add a ${SECTION_TITLES[type] || type} section`);
    } else if (existing.has(type)) {
      const s = site.sections.find((x) => x.type === type);
      changes.push({ sectionId: s.id, instruction: request });
    }
  }
  if (!note.length && !changes.length) {
    note.push("refresh the sections from the latest plan (free-form edits need an LLM provider — configure one in Settings)");
    for (const s of site.sections) changes.push({ sectionId: s.id, instruction: "rebuild" });
  }
  return { thoughts: `To satisfy "${request}" the team should ${note.join(", ")}.`, tokens, changes, newSections, removeSections };
}

export function demoCustom(agent, stage) {
  return stage === "planning"
    ? { thoughts: `${agent.name} (offline) reviewed the plan. Connect a provider for real ${agent.role} guidance.`, guidance: "" }
    : { thoughts: `${agent.name} (offline) reviewed the build. Connect a provider for real ${agent.role} feedback.`, summary: "No changes (offline mode).", changes: [] };
}
