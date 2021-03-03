package main

import (
	"crypto/tls"
	"log"
	"os"
	"time"

	"contrib.go.opencensus.io/exporter/ocagent"
	"github.com/edgelesssys/ego/marble"
	pb "github.com/edgelesssys/emojivoto/emojivoto-web/gen/proto"
	"github.com/edgelesssys/emojivoto/emojivoto-web/web"
	"go.opencensus.io/plugin/ocgrpc"
	"go.opencensus.io/trace"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

var (
	webPort              = os.Getenv("WEB_PORT")
	emojisvcHost         = os.Getenv("EMOJISVC_HOST")
	votingsvcHost        = os.Getenv("VOTINGSVC_HOST")
	indexBundle          = os.Getenv("INDEX_BUNDLE")
	webpackDevServerHost = os.Getenv("WEBPACK_DEV_SERVER")
	ocagentHost          = os.Getenv("OC_AGENT_HOST")
	tlsServer            = os.Getenv("EDG_TLS_SERVER")
)

func main() {
	if webPort == "" || emojisvcHost == "" || votingsvcHost == "" {
		log.Fatalf("WEB_PORT (currently [%s]) EMOJISVC_HOST (currently [%s]) and VOTINGSVC_HOST (currently [%s]) INDEX_BUNDLE (currently [%s]) environment variables must me set.", webPort, emojisvcHost, votingsvcHost, indexBundle)
	}

	// get TLS config
	tlsCfg, err := marble.GetTLSConfig(true)
	if err != nil {
		log.Fatalf("Failed to retrieve server TLS config from ego")
	}

	// create creds
	serverCreds := credentials.NewTLS(tlsCfg)

	oce, err := ocagent.NewExporter(
		ocagent.WithTLSCredentials(serverCreds),
		ocagent.WithReconnectionPeriod(5*time.Second),
		ocagent.WithAddress(ocagentHost),
		ocagent.WithServiceName("web"))
	if err != nil {
		log.Fatalf("Failed to create ocagent-exporter: %v", err)
	}
	trace.RegisterExporter(oce)

	votingSvcConn := openGrpcClientConnection(votingsvcHost)
	votingClient := pb.NewVotingServiceClient(votingSvcConn)
	defer votingSvcConn.Close()

	emojiSvcConn := openGrpcClientConnection(emojisvcHost)
	emojiSvcClient := pb.NewEmojiServiceClient(emojiSvcConn)
	defer emojiSvcConn.Close()

	if tlsServer == "enabled" {
		// Use a different certificate for the web server
		cert := []byte(os.Getenv("WEB_CERT"))
		privk := []byte(os.Getenv("WEB_CERT_KEY"))

		tlsCert, err := tls.X509KeyPair(cert, privk)
		if err != nil {
			log.Fatalf("cannot create TLS cert: %v", err)
		}
		webTLSCfg := &tls.Config{
			Certificates: []tls.Certificate{tlsCert},
		}
		web.StartServer(webPort, webpackDevServerHost, indexBundle, emojiSvcClient, votingClient, webTLSCfg)
	} else {
		web.StartServerNoTLS(webPort, webpackDevServerHost, indexBundle, emojiSvcClient, votingClient)
	}
}

func openGrpcClientConnection(host string) *grpc.ClientConn {
	log.Printf("Connecting to [%s]", host)
	conn, err := grpc.Dial(
		host,
		grpc.WithInsecure(),
		grpc.WithStatsHandler(new(ocgrpc.ClientHandler)))

	if err != nil {
		panic(err)
	}
	return conn
}
