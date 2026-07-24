from validate_export_links import rejection_reason


def test_rejection_reason():
    assert rejection_reason(404, "https://example.com/job") == "http_404"
    assert rejection_reason(200, "https://example.com/jobs?error=true") == "error_redirect"
    assert rejection_reason(403, "https://example.com/job") == ""
    assert rejection_reason(200, "https://example.com/job") == ""
