from pylib_cs._clsc_wsclust_shim_parse_args import cslc_wsclust_shim_parse_args


def test_clsc_wsclust_shim_parse_args():
    assert cslc_wsclust_shim_parse_args(
        ["--help"],
    ) == (None, "--help")
    assert cslc_wsclust_shim_parse_args(
        ["-h"],
    ) == (None, "--help")
    assert cslc_wsclust_shim_parse_args(
        ["foo.csl"],
    ) == ("foo.csl", "")
    assert cslc_wsclust_shim_parse_args(
        ["-o", "outdir", "foo.csl"],
    ) == ("foo.csl", "-o outdir")
    assert cslc_wsclust_shim_parse_args(
        ["--flag=bar", "foo.csl", "-o", "outdir"],
    ) == ("foo.csl", "--flag=bar -o outdir")
