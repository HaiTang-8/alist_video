package proxy

import "testing"

func TestBuildChainedTarget(t *testing.T) {
	r := &Registrar{
		Chain: []ChainHop{
			{Endpoint: "https://hk.example.com", AuthToken: "abc"},
			{Endpoint: "https://sg.example.com", AuthToken: "def"},
		},
	}

	target, headers, err := r.buildChainedTarget("https://cdn.example.com/video.mp4")
	if err != nil {
		t.Fatalf("buildChainedTarget returned error: %v", err)
	}
	if headers.Get("Authorization") != "Bearer abc" {
		t.Fatalf("expected Authorization header for first hop")
	}
	expectedPrefix := "https://hk.example.com/proxy/media"
	if len(target) == 0 || target[:len(expectedPrefix)] != expectedPrefix {
		t.Fatalf("unexpected first hop target: %s", target)
	}
	if target == "https://cdn.example.com/video.mp4" {
		t.Fatalf("target should be wrapped by proxy chain")
	}
}

func TestBuildChainedTargetEmptyChain(t *testing.T) {
	r := &Registrar{}
	target, headers, err := r.buildChainedTarget("https://example.com")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if target != "https://example.com" {
		t.Fatalf("expected original target, got %s", target)
	}
	if len(headers) != 0 {
		t.Fatalf("expected empty headers")
	}
}
