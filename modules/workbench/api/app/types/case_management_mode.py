"""Mode-echoing Matter views used only by the isolated Workbench selector."""

from pydantic import BaseModel

from app.types.case_management import Matter, MatterDetail
from app.types.matter_mode import MatterMode


class ModeBoundMatter(Matter):
    matter_mode: MatterMode


class ModeBoundMatterList(BaseModel):
    data: list[ModeBoundMatter]
    total: int
    limit: int
    offset: int
    matter_mode: MatterMode


class ModeBoundMatterDetail(MatterDetail):
    matter_mode: MatterMode
