// FtlCheck - parse-only FreeMarker syntax check (no data model, no includes resolved).
//   java -cp /usr/share/java/freemarker.jar FtlCheck.java FILE...   exit 0 ok, 1 parse error
// .ftlh / .ftlx get the HTML / XML output format (?no_esc is only legal there).
import freemarker.template.Configuration;
import freemarker.template.Template;
import java.io.Reader;
import java.nio.file.Files;
import java.nio.file.Path;

public class FtlCheck {
    public static void main(String[] args) throws Exception {
        Configuration cfg = new Configuration(Configuration.VERSION_2_3_32);
        cfg.setDefaultEncoding("UTF-8");
        cfg.setTagSyntax(Configuration.AUTO_DETECT_TAG_SYNTAX);
        int bad = 0;
        for (String f : args) {
            if (f.endsWith(".ftlh")) cfg.setOutputFormat(freemarker.core.HTMLOutputFormat.INSTANCE);
            else if (f.endsWith(".ftlx")) cfg.setOutputFormat(freemarker.core.XMLOutputFormat.INSTANCE);
            else cfg.setOutputFormat(freemarker.core.UndefinedOutputFormat.INSTANCE);
            try (Reader r = Files.newBufferedReader(Path.of(f))) {
                new Template(f, r, cfg);
            } catch (freemarker.core.ParseException e) {
                System.out.println(f + ":" + e.getLineNumber() + ":" + e.getColumnNumber() + ": " + e.getEditorMessage());
                bad = 1;
            }
        }
        System.exit(bad);
    }
}
