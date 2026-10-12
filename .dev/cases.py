import re

LP = "[lua:4rtefakt.daily] "
DAY = 'Day="2026-10-13"'


def same_day(out):
    """Two boots on the same day give the same rules and the same result line apart from the time."""
    a, b = out.split("==== second boot")
    ra, rb = re.findall(r"challenge (.+)", a), re.findall(r"challenge (.+)", b)
    return None if ra and ra == rb else f"the two boots differ: {ra} / {rb}"


CASES = {
    # A new game on a fixed day: the day's two rules, 42 shuffled chests, and the same again on a second boot.
    "day": dict(room="S_10/S_1009/S_1009", settings=DAY, drive="60:lua=daily;61:shot;70:lua=daily rules;80:quit",
        drive2="60:lua=daily;70:quit",
        expect=[LP + "Daily Challenge loaded: 2026-10-13", LP + "challenge 2026-10-13: ", LP + "day 2026-10-13 rules ", " chests 42 deaths 0 ",
                LP + "2026-10-13 ", LP + "2026-10-14 ", "==== second boot", LP + "challenge 2026-10-13: "],
        check=same_day, shots={"hud": 61}),
    # Finishing: a death first (kept across the continue), then the final boss's flag: the result code.
    "finish": dict(room="S_10/S_1009/S_1009", settings=DAY,
        drive="60:hp=0;230:ok;290:ok;430:flag=226,1;500:lua=daily;510:quit",
        expect=["[death] HP 0", "notice Daily Challenge complete: YSO-DAILY 2026-10-13 Yunica 0:00:0", LP + "result YSO-DAILY 2026-10-13 Yunica 0:00:0",
                " 1d #", " deaths 1 "]),
    # The first chest of the tower follows the day's layout or keeps its Panacea: either way the box flag opens.
    "chest": dict(room="S_10/S_1001/S_1001", settings=DAY,
        drive="10:kill1;420:obj=box_01;430:act;740:ok;780:lua=daily;790:quit",
        expect=[LP + "challenge 2026-10-13: ", "chest S_1001/S_BOX01 opened (flag 302)", " chests 42 "]),
    # Turned off: an ordinary new game.
    "off": dict(room="S_10/S_1009/S_1009", settings="Enabled=0", drive="60:lua=daily;70:quit",
        expect=[LP + "day - rules - chests 0 deaths 0 atk 46 hp 60/60"], absent=[LP + "challenge "]),
}
