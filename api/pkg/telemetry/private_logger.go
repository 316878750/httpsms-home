package telemetry

import (
	"go.opentelemetry.io/otel/trace"
	"log"
	"os"
	"runtime"
)

// PrivateLogger deliberately never serializes upstream message/error strings:
// many upstream call sites include SMS bodies, credentials and SQL parameters.
type PrivateLogger struct{}

func (l *PrivateLogger) WithService(string) Logger         { return l }
func (l *PrivateLogger) WithString(string, string) Logger  { return l }
func (l *PrivateLogger) WithSpan(trace.SpanContext) Logger { return l }
func (l *PrivateLogger) Info(string)                       {}
func (l *PrivateLogger) Debug(string)                      {}
func (l *PrivateLogger) Trace(string)                      {}
func (l *PrivateLogger) Printf(string, ...interface{})     {}
func (l *PrivateLogger) Error(error)                       { l.write("error") }
func (l *PrivateLogger) Warn(error)                        { l.write("warning") }
func (l *PrivateLogger) Fatal(error)                       { l.write("fatal"); os.Exit(1) }
func (l *PrivateLogger) write(level string) {
	_, file, line, _ := runtime.Caller(2)
	log.Printf("local-hardened %s at %s:%d (details redacted)", level, file, line)
}
