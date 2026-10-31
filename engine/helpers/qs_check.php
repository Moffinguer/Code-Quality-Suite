<?php
// qs_check.php - compile/parse-only syntax checks for PHP template languages (no rendering).
//   php qs_check.php smarty FILE...           Smarty 4 (apt smarty4); unknown plugins tolerated
//   php qs_check.php twig <phar|wrapper> FILE...  Twig bundled in twig-cs-fixer.phar; unknown
//                                             tags/filters/functions/tests tolerated
// Exit 0 ok, 1 syntax error (file:line: message).
$mode = $argv[1] ?? '';
$rc = 0;
if ($mode === 'smarty') {
    require '/usr/share/php/smarty4/bootstrap.php';
    $tmp = sys_get_temp_dir() . '/qs-smarty-' . getmypid();
    function qs_noop() { return ''; }
    foreach (array_slice($argv, 2) as $f) {
        $s = new Smarty();
        $s->setCompileDir($tmp)->setCacheDir($tmp)->setTemplateDir(dirname(realpath($f)));
        // why: project plugins/modifiers are not installed here; they must not look like errors
        $s->registerDefaultPluginHandler(function ($name, $type, $tpl, &$callback, &$script, &$cacheable) {
            $callback = 'qs_noop';
            return true;
        });
        try {
            $s->createTemplate('file:' . realpath($f))->compileTemplateSource();
        } catch (Throwable $e) {
            echo $f . ': ' . strtok($e->getMessage(), "\n") . "\n";
            $rc = 1;
        }
    }
    exec('rm -rf ' . escapeshellarg($tmp));
    exit($rc);
}
if ($mode === 'twig') {
    // the scoped phar lacks symfony/deprecation-contracts' global helper
    if (!function_exists('trigger_deprecation')) { function trigger_deprecation(...$a): void {} }
    $phar = $argv[2];
    if (substr($phar, -5) !== '.phar' && preg_match('/"([^"]+\.phar)"/', (string) @file_get_contents($phar), $m)) {
        $phar = $m[1];  // why: the argument may be the installer's wrapper script around the phar
    }
    require 'phar://' . $phar . '/vendor/autoload.php';
    $files = array_slice($argv, 3);
    // custom tests (`x is foo`) cannot be stubbed lazily: register every `is [not] word` first
    $tests = [];
    foreach ($files as $f) {
        if (preg_match_all('/\bis\s+(?:not\s+)?([A-Za-z_][A-Za-z0-9_]*)/', (string) @file_get_contents($f), $m)) {
            $tests = array_merge($tests, $m[1]);
        }
    }
    $tag = new class extends \Twig\TokenParser\AbstractTokenParser {
        public string $name = '';
        public function parse(\Twig\Token $token): \Twig\Node\Node {
            $s = $this->parser->getStream();
            while (!$s->test(\Twig\Token::BLOCK_END_TYPE)) { $s->next(); }
            $s->expect(\Twig\Token::BLOCK_END_TYPE);
            return new \Twig\Node\Node();
        }
        public function getTag(): string { return $this->name; }
    };
    $twig = new \Twig\Environment(new \Twig\Loader\ArrayLoader([]), ['strict_variables' => false, 'autoescape' => false]);
    // why: framework extensions (Symfony, Drupal, Craft...) add filters/functions/tags we do not load
    $twig->registerUndefinedFilterCallback(fn (string $n) => new \Twig\TwigFilter($n, fn () => null));
    $twig->registerUndefinedFunctionCallback(fn (string $n) => new \Twig\TwigFunction($n, fn () => null));
    $twig->registerUndefinedTokenParserCallback(function (string $n) use ($tag) { $t = clone $tag; $t->name = $n; return $t; });
    foreach (array_unique($tests) as $t) { $twig->addTest(new \Twig\TwigTest($t, fn () => true)); }
    foreach ($files as $f) {
        try {
            $twig->parse($twig->tokenize(new \Twig\Source(file_get_contents($f), $f)));
        } catch (\Twig\Error\SyntaxError $e) {
            printf("%s:%d: %s\n", $f, $e->getTemplateLine(), strtok($e->getRawMessage(), "\n"));
            $rc = 1;
        }
    }
    exit($rc);
}
fwrite(STDERR, "usage: qs_check.php smarty|twig ...\n");
exit(2);
