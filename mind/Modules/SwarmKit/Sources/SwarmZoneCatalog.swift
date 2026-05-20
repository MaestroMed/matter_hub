import Foundation

/// v1.0-alpha.7 — Static reference catalog of 200+ French communes,
/// focused on Île-de-France since every Numelite client is IDF-
/// flavoured. Each entry carries the slug (URL-safe identifier used in
/// the page route), display name, department code, and population
/// (rounded to nearest 100, 2020 INSEE figures).
///
/// The catalog drives the autocomplete in `SwarmWizardSheet`'s
/// Step 1 — Cible. The user can still add a custom zone by hand;
/// the catalog is purely a convenience surface.
///
/// Pure: no I/O, no async, no allocation cost beyond the static
/// `let` array. Sorted alphabetically by display name so the
/// wizard's autocomplete renders in a predictable order.
public enum SwarmZoneCatalog {

    /// The complete catalog. >= 200 zones. Sorted by display name to
    /// ease binary-search and to keep the autocomplete predictable.
    public static let zones: [SwarmZone] = rawZones.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

    /// Lookup by slug. Returns nil when the slug isn't in the
    /// catalog — the wizard falls back to a free-form zone in that
    /// case.
    public static func zone(forSlug slug: String) -> SwarmZone? {
        zones.first(where: { $0.slug == slug })
    }

    /// Filter the catalog by free-text query. Matches case- and
    /// diacritic-insensitively against both `displayName` and `slug`.
    /// Used by the wizard's autocomplete chip search.
    public static func filter(matching query: String) -> [SwarmZone] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return zones }
        let normalized = trimmed
            .folding(options: .diacriticInsensitive, locale: .init(identifier: "en"))
            .lowercased()
        return zones.filter { zone in
            let nameFolded = zone.displayName
                .folding(options: .diacriticInsensitive, locale: .init(identifier: "en"))
                .lowercased()
            return nameFolded.contains(normalized) || zone.slug.contains(normalized)
        }
    }

    // MARK: - Raw seed
    //
    // Population figures are rounded to the nearest hundred from the
    // 2020 INSEE estimates. Where a commune's population is below
    // 5 000 it's omitted (Mehdi's clients don't need to rank in
    // postage-stamp communes). Île-de-France first (departments 75,
    // 77, 78, 91, 92, 93, 94, 95) then a smaller set of regional
    // metro centres so the catalog remains useful outside IDF.

    private static let rawZones: [SwarmZone] = [
        // MARK: 75 — Paris (the 20 arrondissements)
        SwarmZone(slug: "paris-1er", displayName: "Paris 1er", departmentCode: "75", population: 16_900),
        SwarmZone(slug: "paris-2e", displayName: "Paris 2e", departmentCode: "75", population: 20_900),
        SwarmZone(slug: "paris-3e", displayName: "Paris 3e", departmentCode: "75", population: 34_100),
        SwarmZone(slug: "paris-4e", displayName: "Paris 4e", departmentCode: "75", population: 27_800),
        SwarmZone(slug: "paris-5e", displayName: "Paris 5e", departmentCode: "75", population: 58_900),
        SwarmZone(slug: "paris-6e", displayName: "Paris 6e", departmentCode: "75", population: 40_900),
        SwarmZone(slug: "paris-7e", displayName: "Paris 7e", departmentCode: "75", population: 51_400),
        SwarmZone(slug: "paris-8e", displayName: "Paris 8e", departmentCode: "75", population: 36_400),
        SwarmZone(slug: "paris-9e", displayName: "Paris 9e", departmentCode: "75", population: 60_100),
        SwarmZone(slug: "paris-10e", displayName: "Paris 10e", departmentCode: "75", population: 90_400),
        SwarmZone(slug: "paris-11e", displayName: "Paris 11e", departmentCode: "75", population: 145_300),
        SwarmZone(slug: "paris-12e", displayName: "Paris 12e", departmentCode: "75", population: 140_700),
        SwarmZone(slug: "paris-13e", displayName: "Paris 13e", departmentCode: "75", population: 181_500),
        SwarmZone(slug: "paris-14e", displayName: "Paris 14e", departmentCode: "75", population: 137_100),
        SwarmZone(slug: "paris-15e", displayName: "Paris 15e", departmentCode: "75", population: 233_200),
        SwarmZone(slug: "paris-16e", displayName: "Paris 16e", departmentCode: "75", population: 165_400),
        SwarmZone(slug: "paris-17e", displayName: "Paris 17e", departmentCode: "75", population: 167_400),
        SwarmZone(slug: "paris-18e", displayName: "Paris 18e", departmentCode: "75", population: 196_600),
        SwarmZone(slug: "paris-19e", displayName: "Paris 19e", departmentCode: "75", population: 185_900),
        SwarmZone(slug: "paris-20e", displayName: "Paris 20e", departmentCode: "75", population: 195_500),

        // MARK: 92 — Hauts-de-Seine
        SwarmZone(slug: "boulogne-billancourt", displayName: "Boulogne-Billancourt", departmentCode: "92", population: 121_500),
        SwarmZone(slug: "nanterre", displayName: "Nanterre", departmentCode: "92", population: 95_900),
        SwarmZone(slug: "courbevoie", displayName: "Courbevoie", departmentCode: "92", population: 84_300),
        SwarmZone(slug: "asnieres-sur-seine", displayName: "Asnières-sur-Seine", departmentCode: "92", population: 87_100),
        SwarmZone(slug: "colombes", displayName: "Colombes", departmentCode: "92", population: 86_200),
        SwarmZone(slug: "rueil-malmaison", displayName: "Rueil-Malmaison", departmentCode: "92", population: 79_400),
        SwarmZone(slug: "neuilly-sur-seine", displayName: "Neuilly-sur-Seine", departmentCode: "92", population: 62_600),
        SwarmZone(slug: "levallois-perret", displayName: "Levallois-Perret", departmentCode: "92", population: 65_300),
        SwarmZone(slug: "issy-les-moulineaux", displayName: "Issy-les-Moulineaux", departmentCode: "92", population: 69_300),
        SwarmZone(slug: "antony", displayName: "Antony", departmentCode: "92", population: 63_800),
        SwarmZone(slug: "clichy", displayName: "Clichy", departmentCode: "92", population: 63_500),
        SwarmZone(slug: "puteaux", displayName: "Puteaux", departmentCode: "92", population: 45_000),
        SwarmZone(slug: "meudon", displayName: "Meudon", departmentCode: "92", population: 45_900),
        SwarmZone(slug: "suresnes", displayName: "Suresnes", departmentCode: "92", population: 49_100),
        SwarmZone(slug: "clamart", displayName: "Clamart", departmentCode: "92", population: 53_500),
        SwarmZone(slug: "chatillon", displayName: "Châtillon", departmentCode: "92", population: 37_300),
        SwarmZone(slug: "malakoff", displayName: "Malakoff", departmentCode: "92", population: 31_000),
        SwarmZone(slug: "montrouge", displayName: "Montrouge", departmentCode: "92", population: 50_100),
        SwarmZone(slug: "fontenay-aux-roses", displayName: "Fontenay-aux-Roses", departmentCode: "92", population: 24_500),
        SwarmZone(slug: "sceaux", displayName: "Sceaux", departmentCode: "92", population: 20_300),
        SwarmZone(slug: "bagneux", displayName: "Bagneux", departmentCode: "92", population: 41_800),
        SwarmZone(slug: "chaville", displayName: "Chaville", departmentCode: "92", population: 20_500),
        SwarmZone(slug: "sevres", displayName: "Sèvres", departmentCode: "92", population: 23_900),
        SwarmZone(slug: "vanves", displayName: "Vanves", departmentCode: "92", population: 27_900),
        SwarmZone(slug: "saint-cloud", displayName: "Saint-Cloud", departmentCode: "92", population: 30_300),
        SwarmZone(slug: "garches", displayName: "Garches", departmentCode: "92", population: 18_300),
        SwarmZone(slug: "le-plessis-robinson", displayName: "Le Plessis-Robinson", departmentCode: "92", population: 30_300),
        SwarmZone(slug: "chatenay-malabry", displayName: "Châtenay-Malabry", departmentCode: "92", population: 33_700),
        SwarmZone(slug: "bois-colombes", displayName: "Bois-Colombes", departmentCode: "92", population: 29_300),
        SwarmZone(slug: "la-garenne-colombes", displayName: "La Garenne-Colombes", departmentCode: "92", population: 30_000),
        SwarmZone(slug: "villeneuve-la-garenne", displayName: "Villeneuve-la-Garenne", departmentCode: "92", population: 25_700),
        SwarmZone(slug: "gennevilliers", displayName: "Gennevilliers", departmentCode: "92", population: 50_100),

        // MARK: 93 — Seine-Saint-Denis
        SwarmZone(slug: "saint-denis", displayName: "Saint-Denis", departmentCode: "93", population: 113_100),
        SwarmZone(slug: "montreuil", displayName: "Montreuil", departmentCode: "93", population: 109_700),
        SwarmZone(slug: "aubervilliers", displayName: "Aubervilliers", departmentCode: "93", population: 85_700),
        SwarmZone(slug: "aulnay-sous-bois", displayName: "Aulnay-sous-Bois", departmentCode: "93", population: 86_800),
        SwarmZone(slug: "drancy", displayName: "Drancy", departmentCode: "93", population: 70_900),
        SwarmZone(slug: "noisy-le-grand", displayName: "Noisy-le-Grand", departmentCode: "93", population: 68_400),
        SwarmZone(slug: "rosny-sous-bois", displayName: "Rosny-sous-Bois", departmentCode: "93", population: 46_800),
        SwarmZone(slug: "epinay-sur-seine", displayName: "Épinay-sur-Seine", departmentCode: "93", population: 56_200),
        SwarmZone(slug: "bagnolet", displayName: "Bagnolet", departmentCode: "93", population: 35_700),
        SwarmZone(slug: "bondy", displayName: "Bondy", departmentCode: "93", population: 54_400),
        SwarmZone(slug: "bobigny", displayName: "Bobigny", departmentCode: "93", population: 52_900),
        SwarmZone(slug: "le-blanc-mesnil", displayName: "Le Blanc-Mesnil", departmentCode: "93", population: 57_200),
        SwarmZone(slug: "noisy-le-sec", displayName: "Noisy-le-Sec", departmentCode: "93", population: 45_300),
        SwarmZone(slug: "pantin", displayName: "Pantin", departmentCode: "93", population: 59_800),
        SwarmZone(slug: "saint-ouen", displayName: "Saint-Ouen-sur-Seine", departmentCode: "93", population: 51_900),
        SwarmZone(slug: "stains", displayName: "Stains", departmentCode: "93", population: 39_000),
        SwarmZone(slug: "tremblay-en-france", displayName: "Tremblay-en-France", departmentCode: "93", population: 36_200),
        SwarmZone(slug: "le-pre-saint-gervais", displayName: "Le Pré-Saint-Gervais", departmentCode: "93", population: 18_700),
        SwarmZone(slug: "les-lilas", displayName: "Les Lilas", departmentCode: "93", population: 23_400),
        SwarmZone(slug: "romainville", displayName: "Romainville", departmentCode: "93", population: 28_900),
        SwarmZone(slug: "neuilly-plaisance", displayName: "Neuilly-Plaisance", departmentCode: "93", population: 21_300),
        SwarmZone(slug: "villepinte", displayName: "Villepinte", departmentCode: "93", population: 36_800),
        SwarmZone(slug: "sevran", displayName: "Sevran", departmentCode: "93", population: 51_100),
        SwarmZone(slug: "livry-gargan", displayName: "Livry-Gargan", departmentCode: "93", population: 44_400),
        SwarmZone(slug: "clichy-sous-bois", displayName: "Clichy-sous-Bois", departmentCode: "93", population: 30_200),
        SwarmZone(slug: "gagny", displayName: "Gagny", departmentCode: "93", population: 39_700),
        SwarmZone(slug: "le-raincy", displayName: "Le Raincy", departmentCode: "93", population: 14_400),
        SwarmZone(slug: "villemomble", displayName: "Villemomble", departmentCode: "93", population: 28_900),
        SwarmZone(slug: "pierrefitte-sur-seine", displayName: "Pierrefitte-sur-Seine", departmentCode: "93", population: 30_000),

        // MARK: 94 — Val-de-Marne
        SwarmZone(slug: "creteil", displayName: "Créteil", departmentCode: "94", population: 91_200),
        SwarmZone(slug: "vitry-sur-seine", displayName: "Vitry-sur-Seine", departmentCode: "94", population: 95_300),
        SwarmZone(slug: "ivry-sur-seine", displayName: "Ivry-sur-Seine", departmentCode: "94", population: 64_300),
        SwarmZone(slug: "champigny-sur-marne", displayName: "Champigny-sur-Marne", departmentCode: "94", population: 76_800),
        SwarmZone(slug: "saint-maur-des-fosses", displayName: "Saint-Maur-des-Fossés", departmentCode: "94", population: 75_100),
        SwarmZone(slug: "maisons-alfort", displayName: "Maisons-Alfort", departmentCode: "94", population: 56_200),
        SwarmZone(slug: "fontenay-sous-bois", displayName: "Fontenay-sous-Bois", departmentCode: "94", population: 53_700),
        SwarmZone(slug: "vincennes", displayName: "Vincennes", departmentCode: "94", population: 49_700),
        SwarmZone(slug: "le-perreux-sur-marne", displayName: "Le Perreux-sur-Marne", departmentCode: "94", population: 33_800),
        SwarmZone(slug: "joinville-le-pont", displayName: "Joinville-le-Pont", departmentCode: "94", population: 19_900),
        SwarmZone(slug: "nogent-sur-marne", displayName: "Nogent-sur-Marne", departmentCode: "94", population: 33_500),
        SwarmZone(slug: "alfortville", displayName: "Alfortville", departmentCode: "94", population: 44_800),
        SwarmZone(slug: "cachan", displayName: "Cachan", departmentCode: "94", population: 30_400),
        SwarmZone(slug: "kremlin-bicetre", displayName: "Le Kremlin-Bicêtre", departmentCode: "94", population: 26_800),
        SwarmZone(slug: "arcueil", displayName: "Arcueil", departmentCode: "94", population: 22_300),
        SwarmZone(slug: "gentilly", displayName: "Gentilly", departmentCode: "94", population: 17_800),
        SwarmZone(slug: "villejuif", displayName: "Villejuif", departmentCode: "94", population: 57_000),
        SwarmZone(slug: "lhay-les-roses", displayName: "L'Haÿ-les-Roses", departmentCode: "94", population: 31_100),
        SwarmZone(slug: "fresnes", displayName: "Fresnes", departmentCode: "94", population: 26_900),
        SwarmZone(slug: "thiais", displayName: "Thiais", departmentCode: "94", population: 30_300),
        SwarmZone(slug: "choisy-le-roi", displayName: "Choisy-le-Roi", departmentCode: "94", population: 45_900),
        SwarmZone(slug: "orly", displayName: "Orly", departmentCode: "94", population: 24_200),
        SwarmZone(slug: "villeneuve-saint-georges", displayName: "Villeneuve-Saint-Georges", departmentCode: "94", population: 33_900),
        SwarmZone(slug: "saint-mande", displayName: "Saint-Mandé", departmentCode: "94", population: 23_300),
        SwarmZone(slug: "charenton-le-pont", displayName: "Charenton-le-Pont", departmentCode: "94", population: 30_300),
        SwarmZone(slug: "saint-maurice", displayName: "Saint-Maurice", departmentCode: "94", population: 16_000),
        SwarmZone(slug: "bonneuil-sur-marne", displayName: "Bonneuil-sur-Marne", departmentCode: "94", population: 17_500),
        SwarmZone(slug: "boissy-saint-leger", displayName: "Boissy-Saint-Léger", departmentCode: "94", population: 16_800),
        SwarmZone(slug: "chennevieres-sur-marne", displayName: "Chennevières-sur-Marne", departmentCode: "94", population: 18_500),

        // MARK: 78 — Yvelines
        SwarmZone(slug: "versailles", displayName: "Versailles", departmentCode: "78", population: 85_900),
        SwarmZone(slug: "saint-germain-en-laye", displayName: "Saint-Germain-en-Laye", departmentCode: "78", population: 45_700),
        SwarmZone(slug: "sartrouville", displayName: "Sartrouville", departmentCode: "78", population: 52_200),
        SwarmZone(slug: "mantes-la-jolie", displayName: "Mantes-la-Jolie", departmentCode: "78", population: 44_500),
        SwarmZone(slug: "poissy", displayName: "Poissy", departmentCode: "78", population: 38_000),
        SwarmZone(slug: "conflans-sainte-honorine", displayName: "Conflans-Sainte-Honorine", departmentCode: "78", population: 35_400),
        SwarmZone(slug: "houilles", displayName: "Houilles", departmentCode: "78", population: 32_800),
        SwarmZone(slug: "le-chesnay-rocquencourt", displayName: "Le Chesnay-Rocquencourt", departmentCode: "78", population: 32_600),
        SwarmZone(slug: "trappes", displayName: "Trappes", departmentCode: "78", population: 31_600),
        SwarmZone(slug: "montigny-le-bretonneux", displayName: "Montigny-le-Bretonneux", departmentCode: "78", population: 34_400),
        SwarmZone(slug: "rambouillet", displayName: "Rambouillet", departmentCode: "78", population: 26_700),
        SwarmZone(slug: "guyancourt", displayName: "Guyancourt", departmentCode: "78", population: 29_300),
        SwarmZone(slug: "chatou", displayName: "Chatou", departmentCode: "78", population: 30_200),
        SwarmZone(slug: "le-vesinet", displayName: "Le Vésinet", departmentCode: "78", population: 16_900),
        SwarmZone(slug: "maisons-laffitte", displayName: "Maisons-Laffitte", departmentCode: "78", population: 23_800),
        SwarmZone(slug: "elancourt", displayName: "Élancourt", departmentCode: "78", population: 26_100),
        SwarmZone(slug: "plaisir", displayName: "Plaisir", departmentCode: "78", population: 32_100),
        SwarmZone(slug: "carrieres-sous-poissy", displayName: "Carrières-sous-Poissy", departmentCode: "78", population: 17_600),
        SwarmZone(slug: "marly-le-roi", displayName: "Marly-le-Roi", departmentCode: "78", population: 16_800),
        SwarmZone(slug: "voisins-le-bretonneux", displayName: "Voisins-le-Bretonneux", departmentCode: "78", population: 12_500),
        SwarmZone(slug: "fontenay-le-fleury", displayName: "Fontenay-le-Fleury", departmentCode: "78", population: 13_200),

        // MARK: 91 — Essonne
        SwarmZone(slug: "evry-courcouronnes", displayName: "Évry-Courcouronnes", departmentCode: "91", population: 67_500),
        SwarmZone(slug: "corbeil-essonnes", displayName: "Corbeil-Essonnes", departmentCode: "91", population: 51_700),
        SwarmZone(slug: "massy", displayName: "Massy", departmentCode: "91", population: 51_100),
        SwarmZone(slug: "savigny-sur-orge", displayName: "Savigny-sur-Orge", departmentCode: "91", population: 37_200),
        SwarmZone(slug: "viry-chatillon", displayName: "Viry-Châtillon", departmentCode: "91", population: 32_400),
        SwarmZone(slug: "sainte-genevieve-des-bois", displayName: "Sainte-Geneviève-des-Bois", departmentCode: "91", population: 36_500),
        SwarmZone(slug: "athis-mons", displayName: "Athis-Mons", departmentCode: "91", population: 33_700),
        SwarmZone(slug: "palaiseau", displayName: "Palaiseau", departmentCode: "91", population: 33_300),
        SwarmZone(slug: "draveil", displayName: "Draveil", departmentCode: "91", population: 28_800),
        SwarmZone(slug: "yerres", displayName: "Yerres", departmentCode: "91", population: 28_800),
        SwarmZone(slug: "longjumeau", displayName: "Longjumeau", departmentCode: "91", population: 21_400),
        SwarmZone(slug: "ris-orangis", displayName: "Ris-Orangis", departmentCode: "91", population: 28_500),
        SwarmZone(slug: "etampes", displayName: "Étampes", departmentCode: "91", population: 25_500),
        SwarmZone(slug: "brunoy", displayName: "Brunoy", departmentCode: "91", population: 26_200),
        SwarmZone(slug: "montgeron", displayName: "Montgeron", departmentCode: "91", population: 23_700),
        SwarmZone(slug: "bretigny-sur-orge", displayName: "Brétigny-sur-Orge", departmentCode: "91", population: 27_800),
        SwarmZone(slug: "les-ulis", displayName: "Les Ulis", departmentCode: "91", population: 24_700),
        SwarmZone(slug: "vigneux-sur-seine", displayName: "Vigneux-sur-Seine", departmentCode: "91", population: 31_300),
        SwarmZone(slug: "morsang-sur-orge", displayName: "Morsang-sur-Orge", departmentCode: "91", population: 21_300),
        SwarmZone(slug: "juvisy-sur-orge", displayName: "Juvisy-sur-Orge", departmentCode: "91", population: 16_700),

        // MARK: 95 — Val-d'Oise
        SwarmZone(slug: "cergy", displayName: "Cergy", departmentCode: "95", population: 67_300),
        SwarmZone(slug: "argenteuil", displayName: "Argenteuil", departmentCode: "95", population: 110_500),
        SwarmZone(slug: "sarcelles", displayName: "Sarcelles", departmentCode: "95", population: 58_900),
        SwarmZone(slug: "pontoise", displayName: "Pontoise", departmentCode: "95", population: 31_000),
        SwarmZone(slug: "garges-les-gonesse", displayName: "Garges-lès-Gonesse", departmentCode: "95", population: 41_300),
        SwarmZone(slug: "franconville", displayName: "Franconville", departmentCode: "95", population: 36_900),
        SwarmZone(slug: "goussainville", displayName: "Goussainville", departmentCode: "95", population: 32_400),
        SwarmZone(slug: "ermont", displayName: "Ermont", departmentCode: "95", population: 29_900),
        SwarmZone(slug: "eaubonne", displayName: "Eaubonne", departmentCode: "95", population: 25_400),
        SwarmZone(slug: "soisy-sous-montmorency", displayName: "Soisy-sous-Montmorency", departmentCode: "95", population: 18_700),
        SwarmZone(slug: "deuil-la-barre", displayName: "Deuil-la-Barre", departmentCode: "95", population: 22_700),
        SwarmZone(slug: "enghien-les-bains", displayName: "Enghien-les-Bains", departmentCode: "95", population: 11_900),
        SwarmZone(slug: "montmorency", displayName: "Montmorency", departmentCode: "95", population: 21_300),
        SwarmZone(slug: "taverny", displayName: "Taverny", departmentCode: "95", population: 26_700),
        SwarmZone(slug: "herblay-sur-seine", displayName: "Herblay-sur-Seine", departmentCode: "95", population: 31_400),
        SwarmZone(slug: "saint-ouen-laumone", displayName: "Saint-Ouen-l'Aumône", departmentCode: "95", population: 23_700),
        SwarmZone(slug: "domont", displayName: "Domont", departmentCode: "95", population: 15_300),
        SwarmZone(slug: "villiers-le-bel", displayName: "Villiers-le-Bel", departmentCode: "95", population: 27_900),
        SwarmZone(slug: "gonesse", displayName: "Gonesse", departmentCode: "95", population: 26_200),
        SwarmZone(slug: "beauchamp", displayName: "Beauchamp", departmentCode: "95", population: 9_400),
        SwarmZone(slug: "persan", displayName: "Persan", departmentCode: "95", population: 11_700),

        // MARK: 77 — Seine-et-Marne
        SwarmZone(slug: "meaux", displayName: "Meaux", departmentCode: "77", population: 56_000),
        SwarmZone(slug: "chelles", displayName: "Chelles", departmentCode: "77", population: 55_300),
        SwarmZone(slug: "melun", displayName: "Melun", departmentCode: "77", population: 41_400),
        SwarmZone(slug: "pontault-combault", displayName: "Pontault-Combault", departmentCode: "77", population: 37_900),
        SwarmZone(slug: "savigny-le-temple", displayName: "Savigny-le-Temple", departmentCode: "77", population: 31_800),
        SwarmZone(slug: "torcy", displayName: "Torcy", departmentCode: "77", population: 23_400),
        SwarmZone(slug: "champs-sur-marne", displayName: "Champs-sur-Marne", departmentCode: "77", population: 25_900),
        SwarmZone(slug: "lognes", displayName: "Lognes", departmentCode: "77", population: 14_300),
        SwarmZone(slug: "noisiel", displayName: "Noisiel", departmentCode: "77", population: 15_900),
        SwarmZone(slug: "fontainebleau", displayName: "Fontainebleau", departmentCode: "77", population: 13_700),
        SwarmZone(slug: "lagny-sur-marne", displayName: "Lagny-sur-Marne", departmentCode: "77", population: 21_800),
        SwarmZone(slug: "provins", displayName: "Provins", departmentCode: "77", population: 11_700),
        SwarmZone(slug: "dammarie-les-lys", displayName: "Dammarie-lès-Lys", departmentCode: "77", population: 22_500),
        SwarmZone(slug: "le-mee-sur-seine", displayName: "Le Mée-sur-Seine", departmentCode: "77", population: 21_300),
        SwarmZone(slug: "vaux-le-penil", displayName: "Vaux-le-Pénil", departmentCode: "77", population: 11_600),
        SwarmZone(slug: "mitry-mory", displayName: "Mitry-Mory", departmentCode: "77", population: 20_900),
        SwarmZone(slug: "ozoir-la-ferriere", displayName: "Ozoir-la-Ferrière", departmentCode: "77", population: 21_000),
        SwarmZone(slug: "bussy-saint-georges", displayName: "Bussy-Saint-Georges", departmentCode: "77", population: 27_900),
        SwarmZone(slug: "roissy-en-brie", displayName: "Roissy-en-Brie", departmentCode: "77", population: 22_400),
        SwarmZone(slug: "brie-comte-robert", displayName: "Brie-Comte-Robert", departmentCode: "77", population: 17_300),

        // MARK: Regional metro centres outside IDF (for clients with national reach)
        SwarmZone(slug: "lyon", displayName: "Lyon", departmentCode: "69", population: 522_300),
        SwarmZone(slug: "marseille", displayName: "Marseille", departmentCode: "13", population: 873_100),
        SwarmZone(slug: "toulouse", displayName: "Toulouse", departmentCode: "31", population: 498_000),
        SwarmZone(slug: "nice", displayName: "Nice", departmentCode: "06", population: 342_300),
        SwarmZone(slug: "nantes", displayName: "Nantes", departmentCode: "44", population: 320_700),
        SwarmZone(slug: "montpellier", displayName: "Montpellier", departmentCode: "34", population: 302_500),
        SwarmZone(slug: "strasbourg", displayName: "Strasbourg", departmentCode: "67", population: 287_200),
        SwarmZone(slug: "bordeaux", displayName: "Bordeaux", departmentCode: "33", population: 261_800),
        SwarmZone(slug: "lille", displayName: "Lille", departmentCode: "59", population: 234_400),
        SwarmZone(slug: "rennes", displayName: "Rennes", departmentCode: "35", population: 220_500),
        SwarmZone(slug: "reims", displayName: "Reims", departmentCode: "51", population: 181_200),
        SwarmZone(slug: "saint-etienne", displayName: "Saint-Étienne", departmentCode: "42", population: 172_500),
        SwarmZone(slug: "toulon", displayName: "Toulon", departmentCode: "83", population: 175_000),
        SwarmZone(slug: "le-havre", displayName: "Le Havre", departmentCode: "76", population: 165_800),
        SwarmZone(slug: "grenoble", displayName: "Grenoble", departmentCode: "38", population: 158_500),
        SwarmZone(slug: "dijon", displayName: "Dijon", departmentCode: "21", population: 156_900),
        SwarmZone(slug: "angers", displayName: "Angers", departmentCode: "49", population: 154_500),
        SwarmZone(slug: "nimes", displayName: "Nîmes", departmentCode: "30", population: 148_600),
        SwarmZone(slug: "villeurbanne", displayName: "Villeurbanne", departmentCode: "69", population: 153_900),
        SwarmZone(slug: "clermont-ferrand", displayName: "Clermont-Ferrand", departmentCode: "63", population: 146_700),
        SwarmZone(slug: "brest", displayName: "Brest", departmentCode: "29", population: 139_900),
        SwarmZone(slug: "tours", displayName: "Tours", departmentCode: "37", population: 137_000),
        SwarmZone(slug: "amiens", displayName: "Amiens", departmentCode: "80", population: 134_100),
        SwarmZone(slug: "limoges", displayName: "Limoges", departmentCode: "87", population: 130_900),
        SwarmZone(slug: "annecy", displayName: "Annecy", departmentCode: "74", population: 130_700),
        SwarmZone(slug: "perpignan", displayName: "Perpignan", departmentCode: "66", population: 119_700),
        SwarmZone(slug: "metz", displayName: "Metz", departmentCode: "57", population: 116_400),
        SwarmZone(slug: "besancon", displayName: "Besançon", departmentCode: "25", population: 117_900),
        SwarmZone(slug: "orleans", displayName: "Orléans", departmentCode: "45", population: 116_300),
        SwarmZone(slug: "rouen", displayName: "Rouen", departmentCode: "76", population: 112_300),
        SwarmZone(slug: "mulhouse", displayName: "Mulhouse", departmentCode: "68", population: 108_400),
        SwarmZone(slug: "caen", displayName: "Caen", departmentCode: "14", population: 106_300),
        SwarmZone(slug: "nancy", displayName: "Nancy", departmentCode: "54", population: 104_900),
        SwarmZone(slug: "saint-denis-reunion", displayName: "Saint-Denis (974)", departmentCode: "974", population: 153_600),
    ]
}
