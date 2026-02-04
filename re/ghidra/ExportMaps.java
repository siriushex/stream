// Export function map and string xref map to TSV files.
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.symbol.Reference;

public class ExportMaps extends GhidraScript {
    private static final int MAX_STR_LEN = 200;
    private static final String[] DEFAULT_KEYS = new String[] {
        "http_server",
        "srt_input",
        "playlist",
    };

    private static class CallEdge {
        long callerEntry;
        String callerName;
        long calleeEntry;
        String calleeName;
        int count;
    }

    private String asciiSafe(Object value) {
        if (value == null) {
            return "";
        }
        String text = String.valueOf(value);
        StringBuilder out = new StringBuilder(text.length());
        for (int i = 0; i < text.length(); i++) {
            char ch = text.charAt(i);
            if (ch < 128) {
                out.append(ch);
            } else {
                out.append('?');
            }
        }
        String result = out.toString()
            .replace("\r", "\\r")
            .replace("\n", "\\n")
            .replace("\t", "\\t");
        if (result.length() > MAX_STR_LEN) {
            result = result.substring(0, MAX_STR_LEN) + "...";
        }
        return result;
    }

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String outputDir = args.length > 0 ? args[0] : ".";
        String[] keys = args.length > 1 ? Arrays.copyOfRange(args, 1, args.length) : DEFAULT_KEYS;
        String[] keysLower = new String[keys.length];
        for (int i = 0; i < keys.length; i++) {
            keysLower[i] = keys[i].toLowerCase(Locale.ROOT);
        }
        File dir = new File(outputDir);
        if (!dir.isDirectory() && !dir.mkdirs()) {
            throw new RuntimeException("Failed to create output dir: " + dir.getAbsolutePath());
        }

        File funcFile = new File(dir, "func_map.tsv");
        File xrefFile = new File(dir, "xref_map.tsv");
        File funcXrefFile = new File(dir, "func_xref.tsv");
        File callGraphFile = new File(dir, "call_graph.tsv");
        File keyXrefFile = new File(dir, "key_xref.tsv");

        FunctionManager fm = currentProgram.getFunctionManager();
        FunctionIterator funcIter = fm.getFunctions(true);

        try (BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(funcFile), StandardCharsets.US_ASCII))) {
            writer.write("entry\tsize\tname\tis_thunk\tis_external\n");
            while (funcIter.hasNext()) {
                Function func = funcIter.next();
                long entry = func.getEntryPoint().getOffset();
                long size = func.getBody().getNumAddresses();
                writer.write(String.format(
                    "0x%X\t%d\t%s\t%s\t%s\n",
                    entry,
                    size,
                    asciiSafe(func.getName()),
                    func.isThunk(),
                    func.isExternal()
                ));
            }
        }

        FunctionIterator funcIterXref = fm.getFunctions(true);
        Map<String, CallEdge> callEdges = new LinkedHashMap<>();

        try (BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(funcXrefFile), StandardCharsets.US_ASCII))) {
            writer.write("callee_entry\tcallee_name\tcaller_entry\tcaller_name\tcall_site\tref_type\n");
            while (funcIterXref.hasNext()) {
                monitor.checkCancelled();
                Function callee = funcIterXref.next();
                long calleeEntry = callee.getEntryPoint().getOffset();
                String calleeName = asciiSafe(callee.getName());
                Reference[] refs = getReferencesTo(callee.getEntryPoint());
                if (refs == null || refs.length == 0) {
                    continue;
                }
                for (Reference ref : refs) {
                    long refFrom = ref.getFromAddress().getOffset();
                    Function caller = getFunctionContaining(ref.getFromAddress());
                    long callerEntry = caller != null ? caller.getEntryPoint().getOffset() : 0;
                    String callerName = caller != null ? asciiSafe(caller.getName()) : "";
                    String refType = asciiSafe(ref.getReferenceType());
                    writer.write(String.format(
                        "0x%X\t%s\t0x%X\t%s\t0x%X\t%s\n",
                        calleeEntry,
                        calleeName,
                        callerEntry,
                        callerName,
                        refFrom,
                        refType
                    ));
                    if (caller != null && ref.getReferenceType().isCall()) {
                        String key = callerEntry + "->" + calleeEntry;
                        CallEdge edge = callEdges.get(key);
                        if (edge == null) {
                            edge = new CallEdge();
                            edge.callerEntry = callerEntry;
                            edge.callerName = callerName;
                            edge.calleeEntry = calleeEntry;
                            edge.calleeName = calleeName;
                            callEdges.put(key, edge);
                        }
                        edge.count++;
                    }
                }
            }
        }

        try (BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(callGraphFile), StandardCharsets.US_ASCII))) {
            writer.write("caller_entry\tcaller_name\tcallee_entry\tcallee_name\tcall_count\n");
            for (CallEdge edge : callEdges.values()) {
                writer.write(String.format(
                    "0x%X\t%s\t0x%X\t%s\t%d\n",
                    edge.callerEntry,
                    edge.callerName,
                    edge.calleeEntry,
                    edge.calleeName,
                    edge.count
                ));
            }
        }

        Listing listing = currentProgram.getListing();
        DataIterator dataIter = listing.getDefinedData(true);

        try (BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(xrefFile), StandardCharsets.US_ASCII));
             BufferedWriter keyWriter = new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(keyXrefFile), StandardCharsets.US_ASCII))) {
            writer.write("string_addr\tstring\tref_from\tref_func\tref_type\n");
            keyWriter.write("key\tstring_addr\tstring\tref_from\tref_func\tref_type\n");
            while (dataIter.hasNext()) {
                monitor.checkCancelled();
                Data data = dataIter.next();
                if (!data.hasStringValue()) {
                    continue;
                }
                long stringAddr = data.getAddress().getOffset();
                String rawValue = String.valueOf(data.getValue());
                String rawLower = rawValue.toLowerCase(Locale.ROOT);
                String stringValue = asciiSafe(rawValue);
                Reference[] refs = getReferencesTo(data.getAddress());
                boolean[] matchKeys = new boolean[keysLower.length];
                boolean matched = false;
                for (int i = 0; i < keysLower.length; i++) {
                    if (rawLower.contains(keysLower[i])) {
                        matchKeys[i] = true;
                        matched = true;
                    }
                }
                if (refs == null || refs.length == 0) {
                    writer.write(String.format("0x%X\t%s\t\t\t\n", stringAddr, stringValue));
                    if (matched) {
                        for (int i = 0; i < matchKeys.length; i++) {
                            if (!matchKeys[i]) {
                                continue;
                            }
                            keyWriter.write(String.format(
                                "%s\t0x%X\t%s\t\t\t\n",
                                asciiSafe(keys[i]),
                                stringAddr,
                                stringValue
                            ));
                        }
                    }
                    continue;
                }
                for (Reference ref : refs) {
                    long refFrom = ref.getFromAddress().getOffset();
                    Function func = getFunctionContaining(ref.getFromAddress());
                    String funcName = func != null ? asciiSafe(func.getName()) : "";
                    String refType = asciiSafe(ref.getReferenceType());
                    writer.write(String.format(
                        "0x%X\t%s\t0x%X\t%s\t%s\n",
                        stringAddr,
                        stringValue,
                        refFrom,
                        funcName,
                        refType
                    ));
                    if (matched) {
                        for (int i = 0; i < matchKeys.length; i++) {
                            if (!matchKeys[i]) {
                                continue;
                            }
                            keyWriter.write(String.format(
                                "%s\t0x%X\t%s\t0x%X\t%s\t%s\n",
                                asciiSafe(keys[i]),
                                stringAddr,
                                stringValue,
                                refFrom,
                                funcName,
                                refType
                            ));
                        }
                    }
                }
            }
        }
    }
}
