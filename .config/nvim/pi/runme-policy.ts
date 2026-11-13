export const PROD_TIMEOUT_MS = 3000;

const atCommand = (name: string) => new RegExp(`(^|[;&|(\n]|\\$\\()\\s*(sudo\\s+|env\\s+[^;&|]*?\\s)?${name}`);

const DENY: Array<[RegExp, string]> = [
  [/\btmux\s+(kill-|set\s+-s)/, "tmux teardown is never allowed"],
  [/\bctm(stop|start)\b/, "RunMe does not start or stop the dev stack"],
  [atCommand("(kill|pkill|killall)\\b"), "process killing is not allowed"],
  [/\bdocker(-compose|\s+compose)?\s+(down|rm|stop|kill)\b/, "container teardown is not allowed"],
  [atCommand("rm\\s"), "file deletion is not allowed"],
  [/\bgit\s+(push|commit|reset|checkout|switch|rebase|clean|stash|merge|restore)\b/, "git writes are not allowed"],
  [atCommand("(ssh|scp)\\s"), "use runme_prod_sql for production reads"],
  [/RAILS_ENV=production|RACK_ENV=production/, "use runme_prod_sql for production reads"],
  [atCommand("mysql\\s"), "use the mysql_dev tool for local SQL"],
  [/\bdb:(drop|reset|migrate|rollback|schema:load|seed|setup|truncate)/, "schema/data rake tasks are not allowed"],
  [/\bredis-cli\b[^\n]*\b(flush\w*|del|unlink|set|expire)\b/i, "redis writes are not allowed"],
];

const READ_ONLY_SEGMENT =
  /^\s*(rg|grep|cat|ls|head|tail|wc|find|fd|tree|file|stat|which|echo|pwd|sed\s+-n|awk|jq|git\s+(log|show|diff|status|blame|grep|ls-files|rev-parse))\b/;

export function denyReason(command: string): string | undefined {
  for (const [pattern, reason] of DENY) {
    if (pattern.test(command)) return reason;
  }
  return undefined;
}

export function isReadOnlyCommand(command: string): boolean {
  if (/[^>]>(?!&)|>>|\btee\b|\$\(|`/.test(command)) return false;
  return command
    .split(/&&|\|\||[;|]/)
    .filter((segment) => segment.trim() !== "")
    .every((segment) => READ_ONLY_SEGMENT.test(segment));
}

export function prepareProdSql(sql: string, limit: number): string {
  let statement = sql.trim().replace(/;\s*$/, "");
  if (statement.includes(";")) throw new Error("runme_prod_sql accepts exactly one statement");
  if (!/^(SELECT|WITH)\b/i.test(statement)) throw new Error("runme_prod_sql accepts only SELECT or WITH");
  if (/\b(INTO\s+(OUTFILE|DUMPFILE|@)|FOR\s+UPDATE|LOCK\s+IN\s+SHARE\s+MODE|FOR\s+SHARE)\b/i.test(statement)) {
    throw new Error("runme_prod_sql rejects locking reads and SELECT ... INTO");
  }
  if (/^SELECT\b/i.test(statement) && !/MAX_EXECUTION_TIME/i.test(statement)) {
    statement = statement.replace(/^SELECT\b/i, `SELECT /*+ MAX_EXECUTION_TIME(${PROD_TIMEOUT_MS}) */`);
  }
  if (!/\bLIMIT\s+\d+(\s*,\s*\d+|\s+OFFSET\s+\d+)?\s*$/i.test(statement)) {
    statement = `${statement} LIMIT ${limit}`;
  }
  return statement;
}
