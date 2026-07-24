from typing import Annotated

from fastapi import Depends

from fastapi_app.config import Settings, get_settings

SettingsDep = Annotated[Settings, Depends(get_settings)]
