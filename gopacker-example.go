package main

import (
	"encoding/binary"
	"flag"
	"log"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

var static_data map[string]([]byte)

func staticHandler(rw http.ResponseWriter, req *http.Request) {
	var (
		data       []byte
		path       string
		media_type string
		ok         bool
	)

	// Igonre URL parameters, for now. If needed we'll use a web framework.
	path = strings.Split(req.URL.Path, "?")[0]
	//
	if path == "/" {
		http.Redirect(rw, req, "/static/index.html", http.StatusMovedPermanently)
		return
	}

	// We are ignoring the first char as it always starts with "/" for requests. But we don't
	// have "/" in data packed with "gopack.pl" tool.
	if data, ok = static_data[path[1:]]; !ok {
		http.NotFound(rw, req)
		return
	}

	media_type = mime.TypeByExtension(filepath.Ext(path))
	if media_type == "" {
		media_type = http.DetectContentType(data)
	}

	rw.Header().Set("Content-Type", media_type)
	binary.Write(rw, binary.BigEndian, data)
}

func serve(port int) {
	static_data = GetFileMap()
	log.Printf("Serving on port %d.\n", port)

	port_str := strconv.FormatInt(int64(port), 10)

	http.HandleFunc("/", staticHandler)
	if err := http.ListenAndServe("0.0.0.0:"+port_str, nil); err != nil {
		log.Println(err)
		os.Exit(1)
	}
}

func main() {
	port := flag.Int("port", 4050, "run at port")
	flag.Usage = func() {
		log.Printf("usage: %s [--server [--port <port nuber>]]\n", os.Args[0])
		flag.PrintDefaults()
		os.Exit(0)
	}

	flag.Parse()
	serve(*port)
}
