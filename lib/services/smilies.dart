/// f95zone forum smilies. Posts carry them as 1x1 data-URI `<img>`
/// placeholders whose art comes from the site CSS: a `smilie--spriteNNN`
/// class selects either a cell of the emojione sprite sheet (667-697) or a
/// standalone emote PNG (698-710). Those images are bundled under
/// `assets/smilies/` (sliced once from the live sheet), keyed here by the
/// sprite class index with the shortcode kept for text round-trips.
/// Donor emotes (711+) are per-user uploads and stay unmapped; the parser
/// falls back to their shortcode as plain text.
class Smilie {
  final String shortname;
  final String assetPath;

  const Smilie(this.shortname, this.assetPath);
}

const Map<int, Smilie> smiliesBySpriteId = {
  667: Smilie(':)', 'assets/smilies/smile.png'),
  668: Smilie(';)', 'assets/smilies/wink.png'),
  669: Smilie(':(', 'assets/smilies/frown.png'),
  670: Smilie(':mad:', 'assets/smilies/mad.png'),
  671: Smilie(':confused:', 'assets/smilies/confused.png'),
  672: Smilie(':cool:', 'assets/smilies/cool.png'),
  673: Smilie(':p', 'assets/smilies/tongue.png'),
  674: Smilie(':D', 'assets/smilies/biggrin.png'),
  675: Smilie(':eek:', 'assets/smilies/eek.png'),
  676: Smilie(':oops:', 'assets/smilies/oops.png'),
  677: Smilie(':rolleyes:', 'assets/smilies/rolleyes.png'),
  678: Smilie('o_O', 'assets/smilies/erwhat.png'),
  679: Smilie(':cautious:', 'assets/smilies/cautious.png'),
  680: Smilie(':censored:', 'assets/smilies/censored.png'),
  681: Smilie(':cry:', 'assets/smilies/cry.png'),
  682: Smilie(':love:', 'assets/smilies/love.png'),
  683: Smilie(':LOL:', 'assets/smilies/lol.png'),
  684: Smilie(':ROFLMAO:', 'assets/smilies/roflmao.png'),
  685: Smilie(':sick:', 'assets/smilies/sick.png'),
  686: Smilie(':sleep:', 'assets/smilies/sleep.png'),
  687: Smilie(':sneaky:', 'assets/smilies/sneaky.png'),
  688: Smilie('(y)', 'assets/smilies/thumbsup.png'),
  689: Smilie('(n)', 'assets/smilies/thumbsdown.png'),
  690: Smilie(':unsure:', 'assets/smilies/unsure.png'),
  691: Smilie(':whistle:', 'assets/smilies/whistle.png'),
  692: Smilie(':coffee:', 'assets/smilies/coffee.png'),
  693: Smilie(':giggle:', 'assets/smilies/giggle.png'),
  694: Smilie(':alien:', 'assets/smilies/alien.png'),
  695: Smilie(':devilish:', 'assets/smilies/devilish.png'),
  696: Smilie(':geek:', 'assets/smilies/geek.png'),
  697: Smilie(':poop:', 'assets/smilies/poop.png'),
  698: Smilie(':KEK:', 'assets/smilies/kek.png'),
  699: Smilie(':Kappa:', 'assets/smilies/kappa.png'),
  700: Smilie(':4Head:', 'assets/smilies/4head.png'),
  701: Smilie(':BootyTime:', 'assets/smilies/bootytime.png'),
  702: Smilie(':FacePalm:', 'assets/smilies/facepalm.png'),
  703: Smilie(':HideThePain:', 'assets/smilies/hidethepain.png'),
  704: Smilie(':illuminati:', 'assets/smilies/illuminati.png'),
  705: Smilie(':KappaPride:', 'assets/smilies/kappapride.png'),
  706: Smilie(':LUL:', 'assets/smilies/lul.png'),
  707: Smilie(':PogChamp:', 'assets/smilies/pogchamp.png'),
  708: Smilie(':WaitWhat:', 'assets/smilies/waitwhat.png'),
  709: Smilie(':WeSmart:', 'assets/smilies/wesmart.png'),
  710: Smilie(':WutFace:', 'assets/smilies/wutface.png'),
};

final Map<String, Smilie> smiliesByShortname = {
  for (final smilie in smiliesBySpriteId.values) smilie.shortname: smilie,
};
