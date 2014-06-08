STATIC_FILES = $(shell find static/ -follow -type f)

all: gopacker

gopacker: gopacker-example.go gopack.go
	go build

gopack.go: gopack.pl $(STATIC_FILES)
	./gopack.pl static/

clean:
	-@rm gopacker gopack.go 2>/dev/null || true
