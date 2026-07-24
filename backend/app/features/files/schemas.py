"""Response schemas for the files feature."""

from pydantic import BaseModel


class ImageUploadResponse(BaseModel):
    """Result of a generic image upload — a servable URL, no entity binding."""

    remote_url: str
