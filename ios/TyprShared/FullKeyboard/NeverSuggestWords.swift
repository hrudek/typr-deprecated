// The list below is adapted from the List of Dirty, Naughty, Obscene, and Otherwise Bad Words
// (LDNOOBW, revision 5faf2ba42d7b1c0977169ec3611df25a3c08eb13), © 2012–2020 Shutterstock, Inc.,
// and contributors, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), as curated by Hex
// (ios/HEXShared/FullKeyboard/never-suggest.tsv at d65b02d36efbaf1ff771420e89c0632dea4706cb,
// MIT): its German, English and shared lines. Details in THIRD_PARTY_NOTICES.md.
import Foundation

/// Words the keyboard never suggests, autocorrects to or swipes: slurs never, swear words only
/// when asked for or once you have used them yourself.
nonisolated enum NeverSuggestWords {
    enum Kind: Equatable, Sendable { case slur, swear }

    /// The kind of a word or two-word expression, case-insensitive.
    static func kind(of word: String) -> Kind? {
        entries[PersonalLexiconSnapshot.normalize(word)]
    }

    /// Whether `candidate` may not be offered: one of its words (split at spaces and hyphens),
    /// or a two-word expression it forms, also with `previous`, the word before it, is a slur
    /// or a swear word, unless `allowsSwearing` or `isYours` knows it.
    static func blocks(_ candidate: String, after previous: String?, allowsSwearing: Bool,
                       isYours: (String) -> Bool) -> Bool {
        func blocked(_ text: String) -> Bool {
            switch kind(of: text) {
            case .slur: true
            case .swear: !allowsSwearing && !isYours(text)
            case nil: false
            }
        }
        let parts = candidate.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard let first = parts.first else { return false }
        if parts.contains(where: blocked) { return true }
        if let previous, blocked(previous + " " + first) { return true }
        return zip(parts, parts.dropFirst()).contains { blocked($0 + " " + $1) }
    }

    private static let entries: [String: Kind] = {
        var entries: [String: Kind] = [:]
        for line in list.split(separator: "\n") {
            let fields = line.split(separator: "\t")
            guard fields.count == 2 else { continue }
            let word = PersonalLexiconSnapshot.normalize(String(fields[1]))
            if entries[word] != .slur { entries[word] = fields[0] == "slur" ? .slur : .swear }
        }
        return entries
    }()

    private static let list = """
        slur	faggot
        slur	faggots
        slur	nigga
        slur	niggas
        slur	niggaz
        slur	nigger
        slur	niggers
        swear	bullshit
        swear	fuck
        swear	fucked
        swear	fucker
        swear	fuckers
        swear	fuckhead
        swear	fuckheads
        swear	fuckin
        swear	fucking
        swear	fucks
        swear	motherfucker
        swear	motherfuckers
        swear	motherfucking
        swear	shit
        swear	shits
        swear	shitty
        slur	beaner
        slur	beaners
        slur	bimbo
        slur	bimbos
        slur	bulldyke
        slur	bulldykes
        slur	carpet muncher
        slur	carpet munchers
        slur	carpetmuncher
        slur	carpetmunchers
        slur	chink
        slur	chinks
        slur	coon
        slur	coons
        slur	darkie
        slur	darkies
        slur	dyke
        slur	dykes
        slur	fag
        slur	fags
        slur	fucktard
        slur	fucktards
        slur	fudge packer
        slur	fudge packers
        slur	fudgepacker
        slur	fudgepackers
        slur	gook
        slur	gooks
        slur	honkey
        slur	honkeys
        slur	honkie
        slur	honkies
        slur	honky
        slur	jigaboo
        slur	jigaboos
        slur	jiggaboo
        slur	jiggaboos
        slur	jiggerboo
        slur	kike
        slur	kikes
        slur	lesbo
        slur	lesbos
        slur	mong
        slur	mongoloid
        slur	mongoloids
        slur	mongs
        slur	negro
        slur	negroes
        slur	negros
        slur	nig
        slur	nig nog
        slur	nig nogs
        slur	paki
        slur	pakis
        slur	pikey
        slur	pikeys
        slur	pole smoker
        slur	pole smokers
        slur	poof
        slur	poofs
        slur	poofter
        slur	poofters
        slur	raghead
        slur	ragheads
        slur	retard
        slur	retarded
        slur	retards
        slur	shemale
        slur	shemales
        slur	slanteye
        slur	slanteyes
        slur	spastic
        slur	spastics
        slur	spaz
        slur	spazzes
        slur	spic
        slur	spics
        slur	towelhead
        slur	towelheads
        slur	trannies
        slur	tranny
        slur	wetback
        slur	wetbacks
        slur	wop
        slur	wops
        slur	zipperhead
        slur	zipperheads
        swear	apeshit
        swear	arse
        swear	arsehole
        swear	arseholes
        swear	arses
        swear	ass
        swear	asses
        swear	asshat
        swear	asshats
        swear	asshole
        swear	assholes
        swear	assmunch
        swear	asswipe
        swear	asswipes
        swear	ballsack
        swear	ballsacks
        swear	bangbros
        swear	bangbus
        swear	bastard
        swear	bastardo
        swear	bastards
        swear	bastardy
        swear	bitch
        swear	bitched
        swear	bitches
        swear	bitchiness
        swear	bitching
        swear	bitchy
        swear	blow job
        swear	blow jobs
        swear	blowjob
        swear	blowjobs
        swear	blumpkin
        swear	blumpkins
        swear	bollocks
        swear	boner
        swear	boners
        swear	bukkake
        swear	bullshits
        swear	bullshitted
        swear	bullshitter
        swear	bullshitters
        swear	bullshitting
        swear	bunghole
        swear	bungholes
        swear	buttfuck
        swear	buttfucked
        swear	buttfucker
        swear	buttfuckers
        swear	buttfucking
        swear	buttfucks
        swear	butthole
        swear	buttholes
        swear	camgirl
        swear	camgirls
        swear	camslut
        swear	camsluts
        swear	camwhore
        swear	camwhores
        swear	circlejerk
        swear	circlejerks
        swear	clit
        swear	clits
        swear	clusterfuck
        swear	clusterfucks
        swear	cock
        swear	cocks
        swear	cocksucker
        swear	cocksuckers
        swear	cocksucking
        swear	creampie
        swear	creampies
        swear	cum
        swear	cumming
        swear	cums
        swear	cumshot
        swear	cumshots
        swear	cunt
        swear	cunts
        swear	damn
        swear	damned
        swear	damning
        swear	damns
        swear	deepthroat
        swear	dick
        swear	dickhead
        swear	dickheads
        swear	dicks
        swear	dildo
        swear	dildos
        swear	dingleberries
        swear	dingleberry
        swear	doggiestyle
        swear	doggystyle
        swear	dogstyle
        swear	douchebag
        swear	douchebags
        swear	felch
        swear	feltch
        swear	femdom
        swear	figging
        swear	fingerbang
        swear	footjob
        swear	footjobs
        swear	frotting
        swear	gangbang
        swear	gangbangs
        swear	goatcx
        swear	goatse
        swear	goddam
        swear	goddammit
        swear	goddamn
        swear	goddamned
        swear	goddamnit
        swear	gokkun
        swear	goregasm
        swear	hand job
        swear	hand jobs
        swear	handjob
        swear	handjobs
        swear	hentai
        swear	hooker
        swear	hookers
        swear	horseshit
        swear	jackass
        swear	jackasses
        swear	jackoff
        swear	jailbait
        swear	jerkoff
        swear	jizz
        swear	juggs
        swear	knobbing
        swear	knobhead
        swear	knobheads
        swear	livesex
        swear	milf
        swear	milfs
        swear	motherfucked
        swear	motherfuckin
        swear	motherfucks
        swear	muffdiver
        swear	muffdiving
        swear	nympho
        swear	nymphos
        swear	pedobear
        swear	piss
        swear	pissed
        swear	pisser
        swear	pissers
        swear	pisses
        swear	pissing
        swear	pisspig
        swear	pisspigs
        swear	poon
        swear	poontang
        swear	poopchute
        swear	porn
        swear	porno
        swear	punany
        swear	pussies
        swear	pussy
        swear	queaf
        swear	queef
        swear	queefs
        swear	quim
        swear	rimjob
        swear	rimjobs
        swear	rimming
        swear	schlong
        swear	schlongs
        swear	sexcam
        swear	shitblimp
        swear	shite
        swear	shites
        swear	shitfaced
        swear	shithead
        swear	shitheads
        swear	shithole
        swear	shitholes
        swear	shitload
        swear	shitloads
        swear	shitted
        swear	shitting
        swear	shota
        swear	slut
        swear	sluts
        swear	slutty
        swear	splooge
        swear	spooge
        swear	strapon
        swear	throating
        swear	tit
        swear	tits
        swear	titties
        swear	titty
        swear	tosser
        swear	tossers
        swear	tubgirl
        swear	twat
        swear	twats
        swear	upskirt
        swear	voyeurweb
        swear	wank
        swear	wanked
        swear	wanker
        swear	wankers
        swear	wanking
        swear	wanks
        swear	whore
        swear	whores
        swear	worldsex
        swear	yiffy
        slur	analritter
        slur	bimbo
        slur	bimbos
        slur	kampflesbe
        slur	kampflesben
        slur	kanak
        slur	kanake
        slur	kanaken
        slur	kanakin
        slur	kanakinnen
        slur	neger
        slur	negere
        slur	negerin
        slur	negerinnen
        slur	negern
        slur	negers
        slur	schwuchtel
        slur	schwuchteln
        slur	trapse
        slur	trapsen
        slur	zigeuner
        slur	zigeunerin
        slur	zigeunerinnen
        slur	zigeunern
        swear	arsch
        swear	arschficker
        swear	arschkeks
        swear	arschlecker
        swear	arschloch
        swear	arschlöcher
        swear	arschlöchern
        swear	bastard
        swear	bastarde
        swear	beschissen
        swear	bratze
        swear	bumsen
        swear	dödel
        swear	fick
        swear	ficke
        swear	ficken
        swear	ficker
        swear	fickst
        swear	fickt
        swear	fickte
        swear	fickten
        swear	flittchen
        swear	fotze
        swear	fotzen
        swear	gefickt
        swear	hackfresse
        swear	hackfressen
        swear	hure
        swear	huren
        swear	hurensohn
        swear	hurensöhne
        swear	kackbratze
        swear	kacke
        swear	kacken
        swear	kackst
        swear	kackt
        swear	kackwurst
        swear	milf
        swear	morgenlatte
        swear	muschi
        swear	muschis
        swear	möse
        swear	mösen
        swear	nutte
        swear	nutten
        swear	pimmel
        swear	pimpern
        swear	pissen
        swear	pisser
        swear	poppen
        swear	porno
        swear	scheiss
        swear	scheissdreck
        swear	scheisse
        swear	scheissegal
        swear	scheissen
        swear	scheisser
        swear	scheisshaus
        swear	scheisskerl
        swear	scheisst
        swear	scheiß
        swear	scheißdreck
        swear	scheiße
        swear	scheißegal
        swear	scheißen
        swear	scheißer
        swear	scheißhaus
        swear	scheißkerl
        swear	scheißt
        swear	schlampe
        swear	schlampen
        swear	schnackeln
        swear	schwanzlutscher
        swear	tittchen
        swear	titten
        swear	verdammt
        swear	verdammte
        swear	verdammten
        swear	verdammter
        swear	verdammtes
        swear	verfickt
        swear	verfickte
        swear	verfickten
        swear	verfickter
        swear	verficktes
        swear	vollpfosten
        swear	vögeln
        swear	wichse
        swear	wichsen
        swear	wichser
        swear	wichsers
        swear	wichst
        swear	ärsche
        """
}
