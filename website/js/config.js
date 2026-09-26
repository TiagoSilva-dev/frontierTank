/* Where the site's buttons go. Edit this file when deploying; nothing else needs to change.
 *   playUrl   the web game. With the Docker stack (server/docker-compose.yml) the game is
 *             served at /jogar/ next to the site. The language chosen on the site is passed
 *             on as ?lang=pt|en, which the game already understands.
 *   steamUrl  the Steam store page, once it exists ("" shows "em breve").
 */
window.GF_CONFIG = {
  playUrl: "/jogar/",
  steamUrl: "",
};
